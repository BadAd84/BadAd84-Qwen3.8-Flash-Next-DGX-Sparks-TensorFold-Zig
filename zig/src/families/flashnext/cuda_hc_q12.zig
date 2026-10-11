//! The main layers' hyper-connection read-out matrices (each layer's attention and MLP `down` [low (+ the
//! streams' inject rows), wide] and `up` [wide, low], bf16 in the checkpoint) in a lossless 12-bit copy for decode
//! windows (TF_FLASHNEXT_HC_Q12=1). Per (row, 64 k) the maximum exponent `base`; per weight its sign|mantissa byte
//! and a 4-bit exponent offset below `base`, offset 15 escaping to the block's list of exact bits (fn_ops.cu, the
//! format comment above tf_fn_hc_down_q12_kernel). On the checkpoint 0.01-0.03% of weights escape: 77% of the bf16
//! bytes. Built at load on the GPU from the loaded bf16 rows (tf_fn_hc_q12_pack_kernel: escape counts, the host's
//! prefix sums, then the arrays); the bf16 rows stay for prompt chunks and every path the copy does not take.
//! Forward.readoutAt runs a matrix found here through tops.Torch.hcDownQ12 / hcUpMixQ12, with `_b16mm` +
//! `_hc_reduce_act` / `_hc_up_mix`'s bytes (`hc-check`).
const std = @import("std");
const cuda = @import("cuda");
const W = @import("cuda_weights.zig");
const tops = @import("cuda_torch_ops.zig");
const tri = @import("cuda_triton.zig");
const prompt = @import("cuda_prompt.zig");
const lay = @import("cuda_layouts.zig");

const Allocator = std.mem.Allocator;

/// The down kernel's column groups (4 tiles of 8 columns): tops.q12DownTakes refuses a fused launch with more.
pub const max_groups = tops.q12_max_groups;

fn alignUp(v: usize) usize {
    return (v + 255) / 256 * 256;
}

pub const Table = struct {
    map: std.AutoHashMapUnmanaged(u64, tops.Q12) = .empty,
    bufs: std.ArrayList(cuda.DeviceBuffer) = .empty,
    /// max_groups zeroed words: the down kernel's last-CTA counters (each launch leaves them zeroed)
    counters: cuda.DeviceBuffer = undefined,
    have_counters: bool = false,
    bytes_bf16: usize = 0,
    bytes_q12: usize = 0,
    escapes: usize = 0,

    pub fn deinit(t: *Table, gpa: Allocator) void {
        for (t.bufs.items) |*b| b.free();
        t.bufs.deinit(gpa);
        t.map.deinit(gpa);
        if (t.have_counters) t.counters.free();
        t.have_counters = false;
    }

    /// The q12 copy of the bf16 matrix at `weight`.
    pub fn find(t: *const Table, weight: u64) ?tops.Q12 {
        return t.map.get(weight);
    }

    /// Every main layer's attention and MLP read-out down and up matrices of `w` (the MTP layer and the final
    /// mixer keep bf16: the head's 4-bit draft matrices read the mixer's 32-group sums, the copy writes none).
    pub fn build(gpa: Allocator, d: *const cuda.Driver, th: tops.Torch, w: *const W.Weights) !Table {
        var rows: std.ArrayList(W.Rows) = .empty;
        defer rows.deinit(gpa);
        for (w.layers) |l| for ([_]*const W.Hc{ &l.attn_hc, &l.mlp_hc }) |hc| {
            if (hc.down8 == null) try rows.append(gpa, hc.down);
            if (hc.up8 == null) try rows.append(gpa, hc.up);
        };
        return fromRows(gpa, d, th, rows.items);
    }

    /// The table of `rows`' q12 copies and the zeroed counters (build; hc-check's matrices). On an error every device
    /// buffer it allocated is freed once (hc-check's allocation failure pass).
    pub fn fromRows(gpa: Allocator, d: *const cuda.Driver, th: tops.Torch, rows: []const W.Rows) !Table {
        var t: Table = .{};
        errdefer t.deinit(gpa);
        t.counters = try cuda.DeviceBuffer.alloc(d, max_groups * 4);
        t.have_counters = true;
        try t.counters.fill8(0, null);
        var counts = try cuda.DeviceBuffer.alloc(d, 4);
        defer counts.free();
        var host: std.ArrayList(u32) = .empty;
        defer host.deinit(gpa);
        for (rows) |r| try t.add(gpa, d, th, r, &counts, &host);
        return t;
    }

    /// The q12 copy of `r` into the table. On an error the table holds what it held before and `counts` is still one
    /// live buffer (build frees it once).
    pub fn add(t: *Table, gpa: Allocator, d: *const cuda.Driver, th: tops.Torch, r: W.Rows, counts: *cuda.DeviceBuffer, host: *std.ArrayList(u32)) !void {
        if (r.weight == 0 or r.n == 0 or t.map.contains(r.weight)) return;
        const n: usize = r.n;
        const k: usize = r.k;
        if (k % 64 != 0) return error.HcQ12Shape;
        const blocks = (n + 7) / 8 * (k / 64);
        if (counts.len < blocks * 4) {
            // the larger buffer first: a failed allocation leaves the old one for build's free
            const bigger = try cuda.DeviceBuffer.alloc(d, blocks * 4);
            counts.free();
            counts.* = bigger;
        }
        var q: tops.Q12 = .{ .n = n, .k = k };
        try th.hcQ12Pack(r.weight, counts.ptr, q, false);
        try th.s.synchronize();
        try host.resize(gpa, blocks + 1);
        try counts.download(0, std.mem.sliceAsBytes(host.items[1..]));
        host.items[0] = 0;
        var sum: usize = 0;
        for (host.items[1..]) |*c| {
            sum += c.*;
            c.* = @intCast(sum);
        }
        // one buffer: sm, ex, base, escoff, esc (256-byte aligned parts)
        const sm_b = alignUp(blocks * 32 * 16);
        const ex_b = alignUp(blocks * 32 * 8);
        const base_b = alignUp(blocks * 8);
        const off_b = alignUp((blocks + 1) * 4);
        const esc_b = alignUp(@max(sum, 1) * 4);
        // room in the list and the map first, so nothing after the allocation fails but the GPU work, and on that
        // the buffer is freed here and in neither container (Table.deinit frees the list's)
        try t.bufs.ensureUnusedCapacity(gpa, 1);
        try t.map.ensureUnusedCapacity(gpa, 1);
        var buf = try cuda.DeviceBuffer.alloc(d, sm_b + ex_b + base_b + off_b + esc_b);
        errdefer buf.free();
        q.sm = buf.ptr;
        q.ex = buf.ptr + sm_b;
        q.base = q.ex + ex_b;
        q.escoff = q.base + base_b;
        q.esc = q.escoff + off_b;
        try buf.upload(sm_b + ex_b + base_b, std.mem.sliceAsBytes(host.items));
        try th.hcQ12Pack(r.weight, counts.ptr, q, true);
        try th.s.synchronize();
        t.bufs.appendAssumeCapacity(buf);
        t.map.putAssumeCapacityNoClobber(r.weight, q);
        t.bytes_bf16 += n * k * 2;
        t.bytes_q12 += blocks * (32 * 16 + 32 * 8 + 8 + 4) + sum * 4;
        t.escapes += sum;
    }
};

const Fill = enum { normal, wide, cancel, bits };

/// bf16 samples for `fill` (weights: normal, wide exponents 2^-40..2^3 with exact zeros, every bit pattern; inputs:
/// normal, wide, +-pairs with small residues).
fn fillBf16(gpa: Allocator, buf: cuda.DeviceBuffer, count: usize, r: std.Random, fill: Fill) !void {
    const h = try gpa.alloc(u16, count);
    defer gpa.free(h);
    var prev: f32 = 0;
    for (h, 0..) |*v, i| {
        const x: f32 = switch (fill) {
            .normal => r.floatNorm(f32),
            .wide => if (r.uintLessThan(u32, 100) == 0) 0.0 else std.math.ldexp(r.floatNorm(f32), r.intRangeAtMost(i32, -40, 3)),
            .cancel => blk: {
                if (i % 2 == 0) {
                    prev = std.math.ldexp(r.floatNorm(f32), r.intRangeAtMost(i32, 0, 12));
                    break :blk prev;
                }
                break :blk -prev + r.floatNorm(f32) * 1e-3;
            },
            .bits => 0,
        };
        v.* = if (fill == .bits) r.int(u16) else lay.bf16Rne(x);
    }
    try buf.upload(0, std.mem.sliceAsBytes(h));
}

fn same(gpa: Allocator, a: cuda.DeviceBuffer, b: cuda.DeviceBuffer, bytes: usize) !bool {
    const ha = try gpa.alloc(u8, bytes);
    defer gpa.free(ha);
    const hb = try gpa.alloc(u8, bytes);
    defer gpa.free(hb);
    try a.download(0, ha);
    try b.download(0, hb);
    return std.mem.eql(u8, ha, hb);
}

/// `hc-check` (no checkpoint): the q12 down (+ reduce + act) and up (+ mix) against the kernel set's split `_b16mm`
/// + tf_fn_hc_reduce_act_kernel and `_hc_up_mix` (rows > 1) / `_b16mm` + `_hc_mix` (one row): partial, act, inject
/// and mixed bytes at 1-128 rows, inject rows and none, on weights with exponents over 44 binades (escapes) and on
/// every bf16 bit pattern; the reversed-chunk mutant must differ; the table's allocation failure pass (allocCheck);
/// then both timed at decode widths over rotating weight copies (no L2 reuse), eager, back to back.
pub fn check(gpa: Allocator, d: *const cuda.Driver, t: tri.Tri, th0: tops.Torch) !bool {
    const S: usize = 4;
    const LOW: usize = 320;
    const K: usize = 10240;
    const D: usize = 2560;
    const WIDE: usize = S * D;
    const NDN: usize = LOW + S;
    const SK: usize = tri.b16SplitK(NDN, K);
    const max_m: usize = 128;
    const XS: usize = K + 64; // a strided x, as the engine's normed rows
    var th = th0;
    th.s = t.s;
    var prng = std.Random.DefaultPrng.init(0x12b_0c12);
    const r = prng.random();
    var x = try cuda.DeviceBuffer.alloc(d, max_m * XS * 2);
    defer x.free();
    var wd = try cuda.DeviceBuffer.alloc(d, NDN * K * 2);
    defer wd.free();
    var wd2 = try cuda.DeviceBuffer.alloc(d, LOW * K * 2);
    defer wd2.free();
    var wu = try cuda.DeviceBuffer.alloc(d, WIDE * LOW * 2);
    defer wu.free();
    var act = try cuda.DeviceBuffer.alloc(d, max_m * LOW * 2);
    defer act.free();
    var normed = try cuda.DeviceBuffer.alloc(d, max_m * WIDE * 2);
    defer normed.free();
    var up = try cuda.DeviceBuffer.alloc(d, max_m * WIDE * 2);
    defer up.free();
    var xsum = try cuda.DeviceBuffer.alloc(d, max_m * (D / 32) * 4);
    defer xsum.free();
    var bufs: [8]cuda.DeviceBuffer = undefined;
    const sizes = [8]usize{ SK * max_m * NDN * 4, SK * max_m * NDN * 4, max_m * LOW * 2, max_m * LOW * 2, max_m * S * 2, max_m * S * 2, max_m * D * 2, max_m * D * 2 };
    for (&bufs, sizes) |*b, n| b.* = try cuda.DeviceBuffer.alloc(d, n);
    defer for (&bufs) |*b| b.free();
    const p1, const p2, const a1, const a2, const g1, const g2, const m1, const m2 = bufs;
    var all = true;
    var cases: usize = 0;
    var killed: usize = 0;
    var mut_cases: usize = 0;
    for ([_]Fill{ .normal, .wide, .bits }) |wf| {
        try fillBf16(gpa, wd, NDN * K, r, wf);
        // wd2: the first LOW rows of wd at its own address (the no-inject matrix: the table is keyed by address)
        try d.check(d.api.cuMemcpyDtoD_v2(wd2.ptr, wd.ptr, LOW * K * 2), "cuMemcpyDtoD");
        try fillBf16(gpa, wu, WIDE * LOW, r, wf);
        var tab = try Table.fromRows(gpa, d, th, &.{ .{ .weight = wd.ptr, .n = NDN, .k = K }, .{ .weight = wd2.ptr, .n = LOW, .k = K }, .{ .weight = wu.ptr, .n = WIDE, .k = LOW } });
        defer tab.deinit(gpa);
        const qd = tab.find(wd.ptr).?;
        const qd2 = tab.find(wd2.ptr).?;
        const qu = tab.find(wu.ptr).?;
        for ([_]Fill{ .normal, .wide, .cancel }) |xf| {
            try fillBf16(gpa, x, max_m * XS, r, xf);
            try fillBf16(gpa, act, max_m * LOW, r, xf);
            try fillBf16(gpa, normed, max_m * WIDE, r, xf);
            for ([_]usize{ 1, 2, 3, 4, 5, 7, 8, 11, 15, 16, 17, 31, 33, 64, 128 }) |m| {
                for ([_]bool{ true, false }) |inj| {
                    const n: usize = if (inj) NDN else LOW;
                    const w = if (inj) wd.ptr else wd2.ptr;
                    const q = if (inj) qd else qd2;
                    try p1.fill8(0xA5, t.s.handle);
                    for ([_]cuda.DeviceBuffer{ a1, g1 }) |b| try b.fill8(0xA5, t.s.handle);
                    try prompt.b16Slices(t, x.ptr, XS, w, p1.ptr, true, m, n, K);
                    try th.hcReduceAct(p1.ptr, a1.ptr, if (inj) g1.ptr else a1.ptr, m, SK, n, LOW, S);
                    // fused (the last CTA's reduce + act) and partials + tf_fn_hc_reduce_act_kernel
                    for ([_]bool{ true, false }) |fused| {
                        for ([_]cuda.DeviceBuffer{ p2, a2, g2 }) |b| try b.fill8(0x5A, t.s.handle);
                        try th.hcDownQ12(x.ptr, XS, m, q, p2.ptr, a2.ptr, if (inj) g2.ptr else a2.ptr, LOW, S, if (fused) tab.counters.ptr else 0, 0);
                        if (!fused) try th.hcReduceAct(p2.ptr, a2.ptr, if (inj) g2.ptr else a2.ptr, m, SK, n, LOW, S);
                        try t.s.synchronize();
                        var ok = try same(gpa, p1, p2, SK * m * n * 4);
                        ok = ok and try same(gpa, a1, a2, m * LOW * 2);
                        if (inj) ok = ok and try same(gpa, g1, g2, m * S * 2);
                        cases += 1;
                        if (!ok) {
                            all = false;
                            std.debug.print("DIFFER hc q12 down rows {d} ndn {d} weights {s} inputs {s} fused {}\n", .{ m, n, @tagName(wf), @tagName(xf), fused });
                        }
                    }
                    if (wf != .bits and (m == 3 or m == 33)) {
                        try th.hcDownQ12(x.ptr, XS, m, q, p2.ptr, a2.ptr, if (inj) g2.ptr else a2.ptr, LOW, S, tab.counters.ptr, 1);
                        try t.s.synchronize();
                        mut_cases += 1;
                        if (!try same(gpa, p1, p2, SK * m * n * 4)) killed += 1;
                    }
                }
                try m1.fill8(0xA5, t.s.handle);
                try m2.fill8(0x5A, t.s.handle);
                if (m > 1) {
                    try prompt.upMix(t, act.ptr, wu.ptr, normed.ptr, m1.ptr, m, D, S, LOW, 32);
                } else {
                    try t.b16mm(act.ptr, LOW, wu.ptr, up.ptr, false, 0, m, WIDE, LOW);
                    try t.hcMix(up.ptr, normed.ptr, m1.ptr, xsum.ptr, m, D, S);
                }
                try th.hcUpMixQ12(act.ptr, qu, normed.ptr, m2.ptr, m, D, 0);
                try t.s.synchronize();
                cases += 1;
                if (!try same(gpa, m1, m2, m * D * 2)) {
                    all = false;
                    std.debug.print("DIFFER hc q12 upmix rows {d} weights {s} inputs {s}\n", .{ m, @tagName(wf), @tagName(xf) });
                }
                if (wf != .bits and (m == 3 or m == 33)) {
                    try th.hcUpMixQ12(act.ptr, qu, normed.ptr, m2.ptr, m, D, 1);
                    try t.s.synchronize();
                    mut_cases += 1;
                    if (!try same(gpa, m1, m2, m * D * 2)) killed += 1;
                }
            }
        }
        std.debug.print("weights {s}: q12 {d} escapes, {d:.4} of the bf16 bytes\n", .{ @tagName(wf), tab.escapes, @as(f64, @floatFromInt(tab.bytes_q12)) / @as(f64, @floatFromInt(tab.bytes_bf16)) });
    }
    std.debug.print("{s} hc q12: {d} cases (down + reduce + act against the split _b16mm + tf_fn_hc_reduce_act_kernel; up + mix against _hc_up_mix / _b16mm + _hc_mix), mutant killed {d} of {d}\n", .{ if (all) "EQUAL" else "DIFFER", cases, killed, mut_cases });
    if (killed == 0) all = false;
    if (!try allocCheck(gpa, d, th)) all = false;
    try timing(gpa, d, t, th);
    return all;
}

/// `hc-check`'s allocation failure pass: Table.fromRows with each host allocation failing in turn, then each device
/// allocation (cuMemAlloc / cuMemFree hooked in a copy of the driver), until a run reaches no failure point. Every
/// run must return OutOfMemory / OutOfDeviceMemory exactly when a failure was injected (else a whole table), free each
/// device buffer it allocated once, and free none twice. Three matrices; the third takes a larger escape-count buffer
/// than the first two (the path that replaces it).
fn allocCheck(gpa: Allocator, d: *const cuda.Driver, th: tops.Torch) !bool {
    const abi = cuda.abi;
    const Hook = struct {
        var real_alloc: @FieldType(abi.Api, "cuMemAlloc_v2") = undefined;
        var real_free: @FieldType(abi.Api, "cuMemFree_v2") = undefined;
        var live: [64]abi.DevicePtr = undefined;
        var n_live: usize = 0;
        var twice: usize = 0;
        var calls: usize = 0;
        var fail_at: usize = 0;
        fn alloc(p: *abi.DevicePtr, len: usize) callconv(.c) abi.Result {
            calls += 1;
            if (calls == fail_at or n_live == live.len) return 2; // CUDA_ERROR_OUT_OF_MEMORY
            const res = real_alloc(p, len);
            if (res == abi.success) {
                live[n_live] = p.*;
                n_live += 1;
            }
            return res;
        }
        fn free(p: abi.DevicePtr) callconv(.c) abi.Result {
            for (live[0..n_live], 0..) |v, i| if (v == p) {
                live[i] = live[n_live - 1];
                n_live -= 1;
                return real_free(p);
            };
            twice += 1;
            return 1; // CUDA_ERROR_INVALID_VALUE: not a live allocation (already freed)
        }
    };
    Hook.real_alloc = d.api.cuMemAlloc_v2;
    Hook.real_free = d.api.cuMemFree_v2;
    var dd = d.*;
    dd.api.cuMemAlloc_v2 = &Hook.alloc;
    dd.api.cuMemFree_v2 = &Hook.free;
    const shapes = [3][2]usize{ .{ 16, 640 }, .{ 8, 640 }, .{ 64, 1280 } };
    var w: [3]cuda.DeviceBuffer = undefined;
    var rows: [3]W.Rows = undefined;
    var prng = std.Random.DefaultPrng.init(0xa110c);
    for (&w, &rows, shapes, 0..) |*b, *r, s, i| {
        errdefer for (w[0..i]) |*o| o.free();
        b.* = try cuda.DeviceBuffer.alloc(d, s[0] * s[1] * 2);
        try fillBf16(gpa, b.*, s[0] * s[1], prng.random(), .wide);
        r.* = .{ .weight = b.ptr, .n = @intCast(s[0]), .k = @intCast(s[1]) };
    }
    defer for (&w) |*b| b.free();
    var runs: usize = 0;
    var bad: usize = 0;
    for ([_]bool{ false, true }) |device| {
        var i: usize = 0;
        while (true) : (i += 1) {
            Hook.calls = 0;
            Hook.fail_at = if (device) i + 1 else 0;
            Hook.twice = 0;
            Hook.n_live = 0;
            var fa = std.testing.FailingAllocator.init(gpa, .{ .fail_index = if (device) std.math.maxInt(usize) else i });
            const a = fa.allocator();
            var ok = true;
            if (Table.fromRows(a, &dd, th, &rows)) |built| {
                var tab = built;
                tab.deinit(a);
                if (fa.has_induced_failure or (device and Hook.calls >= Hook.fail_at)) ok = false;
            } else |err| {
                if (err != error.OutOfMemory and err != error.OutOfDeviceMemory) ok = false;
            }
            const injected = if (device) Hook.calls >= Hook.fail_at else fa.has_induced_failure;
            if (Hook.twice != 0 or Hook.n_live != 0) ok = false;
            runs += 1;
            if (!ok) {
                bad += 1;
                std.debug.print("DIFFER hc q12 table: {s} allocation {d} failing: {d} buffers freed twice, {d} not freed\n", .{ if (device) "device" else "host", i + 1, Hook.twice, Hook.n_live });
            }
            if (!injected) break;
        }
    }
    std.debug.print("{s} hc q12 table allocation failures: {d} runs, {d} wrong\n", .{ if (bad == 0) "EQUAL" else "DIFFER", runs, bad });
    return bad == 0;
}

/// Decode-width timing: NC read-outs over distinct weight copies (> 3x L2), the kernel set's down + reduce-act +
/// up-mix against the q12 pair; eager, back to back, best of 3 passes of 4 rounds.
fn timing(gpa: Allocator, d: *const cuda.Driver, t: tri.Tri, th: tops.Torch) !void {
    const NC = 24;
    const S: usize = 4;
    const LOW: usize = 320;
    const K: usize = 10240;
    const D: usize = 2560;
    const WIDE: usize = S * D;
    const NDN: usize = LOW + S;
    const SK: usize = tri.b16SplitK(NDN, K);
    var prng = std.Random.DefaultPrng.init(0x71_3e);
    const r = prng.random();
    var wd: [NC]cuda.DeviceBuffer = undefined;
    var wu: [NC]cuda.DeviceBuffer = undefined;
    for (&wd, &wu) |*a, *b| {
        a.* = try cuda.DeviceBuffer.alloc(d, NDN * K * 2);
        b.* = try cuda.DeviceBuffer.alloc(d, WIDE * LOW * 2);
        try fillBf16(gpa, a.*, NDN * K, r, .normal);
        try fillBf16(gpa, b.*, WIDE * LOW, r, .normal);
    }
    defer for (&wd, &wu) |*a, *b| {
        a.free();
        b.free();
    };
    var rows: [2 * NC]W.Rows = undefined;
    for (wd, wu, 0..) |a, b, i| {
        rows[2 * i] = .{ .weight = a.ptr, .n = NDN, .k = K };
        rows[2 * i + 1] = .{ .weight = b.ptr, .n = WIDE, .k = LOW };
    }
    var tab = try Table.fromRows(gpa, d, th, &rows);
    defer tab.deinit(gpa);
    const max_m = 16;
    var x = try cuda.DeviceBuffer.alloc(d, max_m * K * 2);
    defer x.free();
    var part = try cuda.DeviceBuffer.alloc(d, SK * max_m * NDN * 4);
    defer part.free();
    var act = try cuda.DeviceBuffer.alloc(d, max_m * LOW * 2);
    defer act.free();
    var inj = try cuda.DeviceBuffer.alloc(d, max_m * S * 2);
    defer inj.free();
    var normed = try cuda.DeviceBuffer.alloc(d, max_m * WIDE * 2);
    defer normed.free();
    var up = try cuda.DeviceBuffer.alloc(d, max_m * WIDE * 2);
    defer up.free();
    var mixed = try cuda.DeviceBuffer.alloc(d, max_m * D * 2);
    defer mixed.free();
    var xsum = try cuda.DeviceBuffer.alloc(d, max_m * (D / 32) * 4);
    defer xsum.free();
    try fillBf16(gpa, x, max_m * K, r, .normal);
    try fillBf16(gpa, act, max_m * LOW, r, .normal);
    try fillBf16(gpa, normed, max_m * WIDE, r, .normal);
    var e0 = try cuda.Event.init(d, true);
    defer e0.deinit();
    var e1 = try cuda.Event.init(d, true);
    defer e1.deinit();
    var e2 = try cuda.Event.init(d, true);
    defer e2.deinit();
    for ([_]usize{ 1, 2, 4, 5, 8, 12, 16 }) |m| {
        var best = [2]f32{ 1e9, 1e9 };
        for (0..3) |_| {
            try e0.record(t.s);
            for (0..4) |_| for (wd, wu) |a, b| {
                try prompt.b16Slices(t, x.ptr, K, a.ptr, part.ptr, true, m, NDN, K);
                try th.hcReduceAct(part.ptr, act.ptr, inj.ptr, m, SK, NDN, LOW, S);
                if (m > 1) {
                    try prompt.upMix(t, act.ptr, b.ptr, normed.ptr, mixed.ptr, m, D, S, LOW, 32);
                } else {
                    try t.b16mm(act.ptr, LOW, b.ptr, up.ptr, false, 0, m, WIDE, LOW);
                    try t.hcMix(up.ptr, normed.ptr, mixed.ptr, xsum.ptr, m, D, S);
                }
            };
            try e1.record(t.s);
            for (0..4) |_| for (wd, wu) |a, b| {
                // the forward's choices: reduce + act fused to 8 rows, the q12 up to 16 rows
                try th.hcDownQ12(x.ptr, K, m, tab.find(a.ptr).?, part.ptr, act.ptr, inj.ptr, LOW, S, if (m <= 8) tab.counters.ptr else 0, 0);
                if (m > 8) try th.hcReduceAct(part.ptr, act.ptr, inj.ptr, m, SK, NDN, LOW, S);
                try th.hcUpMixQ12(act.ptr, tab.find(b.ptr).?, normed.ptr, mixed.ptr, m, D, 0);
            };
            try e2.record(t.s);
            try e2.synchronize();
            best[0] = @min(best[0], try cuda.Event.elapsedMs(e0, e1) / (4 * NC));
            best[1] = @min(best[1], try cuda.Event.elapsedMs(e1, e2) / (4 * NC));
        }
        std.debug.print("bench hc read-out {d} rows: kernel set {d:.2} us, q12 {d:.2} us ({d:.3}x); x97 a round: {d:.3} -> {d:.3} ms\n", .{ m, best[0] * 1000, best[1] * 1000, best[0] / best[1], best[0] * 97, best[1] * 97 });
    }
}
