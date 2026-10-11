//! 128x128-block FP8 linears (ModelOpt FP8_PB_WO: e4m3 `weight` + fp32 `weight_scale_inv`) on CUDA, as the Python
//! engine runs them (cuda/nvfp4/linear.py Fp8BlockLinear): e4m3 bytes in the FP8 GEMM's fragment order, an fp32
//! scale per (64 inputs, output column), and the lane matmul in mode FP8G (qmmf.cu) for decode and prompt rows
//! alike: each 64 inputs' bf16 MMA products scaled into an fp32 sum in block order, K slices fixed by the shape, a
//! row's bits independent of every other row and of M. zig/kernels/cuda/fn_qmmf.cu is the device code copied by
//! zig/tests/cuda/copies.py (SASS-equal to the Python extension tensorfold_nvfp4_v3); `matmul` is linear._matmul and
//! qmmf_cuda's host logic. The host layout helpers make the loader's buffers byte for byte as from_checkpoint does.
//!
//! Python source (TensorFold, https://github.com/ashhart/TensorFold, cuda/nvfp4/linear.py and qmmf.cu, authored by
//! Ash Hart (ashhart)).
const std = @import("std");
const cuda = @import("cuda");
/// The shared count-setting reader (refuses a value that is not a count).
const envCount = @import("cuda_engine.zig").envCount;

/// Fp8BlockLinear: w8 uint8 [npad/64][K/64][8][32][2][8] (fragment order), bs fp32 [npad/64][K/64][64].
pub const Linear = struct { w8: u64 = 0, bs: u64 = 0, n: u32 = 0, k: u32 = 0, npad: u32 = 0 };

/// linear.py FUSED_ROWS (TF_QMMF_FUSED_ROWS default): rows from which a block sums its tile's K slices itself.
pub const fused_rows: usize = 256;

/// Rows of output padding Fp8Linear / Fp8BlockLinear take: ceil(n / 128) * 128.
pub fn npadOf(n: usize) usize {
    return (n + 127) / 128 * 128;
}

/// qmm.split_k(n, k, gs=64, target=192): K slices fixed by the weight's shape, never by the row count.
pub fn splitK(n: usize, k: usize) usize {
    const tiles = (n + 63) / 64;
    const groups = k / 64;
    var sk: usize = 1;
    while (sk < 8 and tiles * sk < 192 and groups % (sk * 2) == 0 and groups / (sk * 2) >= 8) sk *= 2;
    return sk;
}

/// qmm.bucket: the row tile.
pub fn bucket(m: usize) usize {
    return if (m <= 16) 16 else if (m <= 32) 32 else 64;
}

/// qmmf.cu Tile<FP8G, BM, 64, 1, 4, 4>::SMEM: max(4 stages, the cluster partials).
pub fn smem(bm: usize) u32 {
    return smemS(bm, 4);
}

/// Tile<FP8G, BM, 64, 1, 4, STAGES>::SMEM.
pub fn smemS(bm: usize, stages: usize) u32 {
    const stage = std.mem.alignForward(usize, bm * 128 + 64 * 64 + 64 * 4, 128);
    const partials = (bm / 16) * 2 * 4 * 128 * 4;
    return @intCast(@max(stages * stage, partials));
}

/// How split-K shapes below FUSED_ROWS run (fp8-fused-check: the same bits as the cluster kernel): `fuse` 0 on the
/// cluster kernel (one block a K slice, the slices added in the cluster), 4 or 8 on the fused form (one block a
/// 64-column tile walks its K slices and adds them in slice order, as the cluster does) at that pipeline depth for
/// row tiles 16 and 32 (row tile 64 takes the prompt's fused kernel). Only shapes of at least `fuse_n` columns (n /
/// 64 blocks walk all slices; a narrow shape such as the MTP layer's hyper-connection down, a few column tiles over
/// K 10240, would leave the GPU nearly empty: measured 0.51 -> 1.16 ms a round). TF_FLASHNEXT_FP8_FUSED_SPLIT (0, 4,
/// 8) and TF_FLASHNEXT_FP8_FUSED_SPLIT_N. `mutant` (fp8-fused-check only, never from the environment): the fused
/// form told half the slices, which the check must see.
pub const Mode = struct { fuse: u8 = 0, fuse_n: usize = 2048, mutant: bool = false };

pub fn modeFromEnv() !Mode {
    const fu = (try envCount("TF_FLASHNEXT_FP8_FUSED_SPLIT") orelse 0);
    if (fu != 0 and fu != 4 and fu != 8) {
        std.log.warn("TF_FLASHNEXT_FP8_FUSED_SPLIT={d} refused: 0 (the cluster kernel), 4 or 8 (pipeline depths)", .{fu});
        return error.BadSetting;
    }
    const m: Mode = .{ .fuse = @intCast(fu), .fuse_n = (try envCount("TF_FLASHNEXT_FP8_FUSED_SPLIT_N") orelse 2048) };
    if (m.fuse != 0) {
        std.log.info("block-FP8 split-K shapes of {d}+ columns below {d} rows: one block a column tile, its K slices in slice order (TF_FLASHNEXT_FP8_FUSED_SPLIT={d})", .{ m.fuse_n, fused_rows, m.fuse });
    } else std.log.info("block-FP8 split-K shapes below {d} rows on the cluster kernel (TF_FLASHNEXT_FP8_FUSED_SPLIT=0)", .{fused_rows});
    return m;
}

/// qmmf.cu launch's L2 band: row tiles whose inputs fill about 12 MB.
pub fn l2Group(rows_t: usize, bm: usize, k: usize) usize {
    return @max(1, @min(rows_t, (12 << 20) / (bm * k * 2)));
}

/// Mangled names of the FP8G instantiations (fn_qmmf.cu's footer): [F32][cluster][bm 16, 32, 64], and the fused [F32].
pub const sym = struct {
    fn name(comptime bm: u32, comptime f32_out: bool, comptime cluster: bool, comptime fuse: bool) [:0]const u8 {
        return nameS(bm, f32_out, cluster, fuse, 4);
    }
    fn nameS(comptime bm: u32, comptime f32_out: bool, comptime cluster: bool, comptime fuse: bool, comptime st: u32) [:0]const u8 {
        return std.fmt.comptimePrint("_ZN10tf_fn_qmmf11qmmf_kernelILi3ELi{d}ELi64ELi1ELi4ELi{d}ELb{d}ELb{d}ELb{d}EEEvPK13__nv_bfloat16PKhS5_fPvPfiiiiiii", .{ bm, st, @intFromBool(f32_out), @intFromBool(cluster), @intFromBool(fuse) });
    }
    pub const tiled = blk: {
        var out: [2][2][3][:0]const u8 = undefined;
        for (0..2) |f| for (0..2) |c| for (0..3) |b| {
            out[f][c][b] = name(16 << b, f == 1, c == 1, false);
        };
        break :blk out;
    };
    pub const fused = [2][:0]const u8{ name(64, false, false, true), name(64, true, false, true) };
    /// the fused form at the decode row tiles (Mode.fuse): [depth 4, 8][F32][bm 16, 32]
    pub const fuse_s = blk: {
        var out: [2][2][2][:0]const u8 = undefined;
        for (0..2) |q| for (0..2) |f| for (0..2) |b| {
            out[q][f][b] = nameS(16 << b, f == 1, false, true, 4 + 4 * q);
        };
        break :blk out;
    };
    /// fn_qmmf_ld.cu's (tools/zig/flashnext_qmmf_ld.py): bf16 out with a row stride, [cluster][bm 16, 32, 64] and fused
    fn ldName(comptime bm: u32, comptime cluster: bool, comptime fuse: bool) [:0]const u8 {
        return ldNameS(bm, cluster, fuse, 4);
    }
    fn ldNameS(comptime bm: u32, comptime cluster: bool, comptime fuse: bool, comptime st: u32) [:0]const u8 {
        return std.fmt.comptimePrint("_ZN13tf_fn_qmmf_ld11qmmf_kernelILi3ELi{d}ELi64ELi1ELi4ELi{d}ELb0ELb{d}ELb{d}EEEvPK13__nv_bfloat16PKhS5_fPvPfiiiiiiii", .{ bm, st, @intFromBool(cluster), @intFromBool(fuse) });
    }
    pub const ld_tiled = blk: {
        var out: [2][3][:0]const u8 = undefined;
        for (0..2) |c| for (0..3) |b| {
            out[c][b] = ldName(16 << b, c == 1, false);
        };
        break :blk out;
    };
    pub const ld_fused = ldName(64, false, true);
    pub const ld_fuse_s = blk: {
        var out: [2][2][:0]const u8 = undefined;
        for (0..2) |q| for (0..2) |b| {
            out[q][b] = ldNameS(16 << b, false, true, 4 + 4 * q);
        };
        break :blk out;
    };
};

pub const Kernels = struct {
    module: cuda.Module,
    tiled: [2][2][3]cuda.Function, // [bf16, fp32][one slice, cluster][16, 32, 64]
    fused: [2]cuda.Function,
    /// fn_qmmf_ld: the same kernels writing bf16 rows `ldo` apart
    ld_module: cuda.Module,
    ld_tiled: [2][3]cuda.Function,
    ld_fused: cuda.Function,
    /// the fused decode tiles (Mode.fuse): [depth 4, 8][F32][bm 16, 32], and their ld forms
    fuse_s: [2][2][2]cuda.Function,
    ld_fuse_s: [2][2]cuda.Function,
    mode: Mode,
    major: c_int,

    pub fn load(ctx: *const cuda.Context) !Kernels {
        if (!cuda.kernels.available) return error.BuiltWithoutKernels;
        var k: Kernels = undefined;
        k.module = try cuda.Module.load(ctx.d, cuda.kernels.fn_qmmf);
        errdefer k.module.unload();
        for (0..2) |f| {
            for (0..2) |c| for (0..3) |b| {
                k.tiled[f][c][b] = try k.module.function(sym.tiled[f][c][b]);
                try k.tiled[f][c][b].allowDynamicShared(smem(@as(usize, 16) << @intCast(b)));
            };
            k.fused[f] = try k.module.function(sym.fused[f]);
            try k.fused[f].allowDynamicShared(smem(64));
        }
        k.ld_module = try cuda.Module.load(ctx.d, cuda.kernels.fn_qmmf_ld);
        errdefer k.ld_module.unload();
        for (0..2) |c| for (0..3) |b| {
            k.ld_tiled[c][b] = try k.ld_module.function(sym.ld_tiled[c][b]);
            try k.ld_tiled[c][b].allowDynamicShared(smem(@as(usize, 16) << @intCast(b)));
        };
        k.ld_fused = try k.ld_module.function(sym.ld_fused);
        try k.ld_fused.allowDynamicShared(smem(64));
        for (0..2) |q| {
            for (0..2) |f| for (0..2) |b| {
                k.fuse_s[q][f][b] = try k.module.function(sym.fuse_s[q][f][b]);
                try k.fuse_s[q][f][b].allowDynamicShared(smemS(@as(usize, 16) << @intCast(b), 4 + 4 * q));
            };
            for (0..2) |b| {
                k.ld_fuse_s[q][b] = try k.ld_module.function(sym.ld_fuse_s[q][b]);
                try k.ld_fuse_s[q][b].allowDynamicShared(smemS(@as(usize, 16) << @intCast(b), 4 + 4 * q));
            }
        }
        k.mode = try modeFromEnv();
        k.major = try ctx.attribute(.compute_capability_major);
        return k;
    }

    pub fn deinit(k: *Kernels) void {
        k.ld_module.unload();
        k.module.unload();
    }
};

fn bucketIndex(bm: usize) usize {
    return switch (bm) {
        16 => 0,
        32 => 1,
        else => 2,
    };
}

/// linear._matmul(FP8G, ...) and qmmf_cuda: x (m, K) bf16 rows `x_stride` elements apart -> out (m, n) bf16 (fp32
/// with `f32_out`), contiguous. K slices from the shape alone (split_k), added in a cluster (sm_90 on) or, from
/// FUSED_ROWS rows, by each block in slice order: the same bits either way, a row's bits never depend on m.
pub fn matmul(k: *const Kernels, s: cuda.Stream, x: u64, x_stride: usize, l: Linear, out: u64, f32_out: bool, m: usize) !void {
    return matmulAt(k, s, x, x_stride, l, out, f32_out, m, null);
}

/// `matmul`, bf16 out, the rows `ldo` elements apart (fn_qmmf_ld: the same kernels and values, only the store
/// address differs; a projection's block-FP8 columns written straight into its wider rows).
pub fn matmulLd(k: *const Kernels, s: cuda.Stream, x: u64, x_stride: usize, l: Linear, out: u64, ldo: usize, m: usize) !void {
    if (ldo < l.n or ldo % 2 != 0 or out % 4 != 0) return error.Invalid;
    return matmulAt(k, s, x, x_stride, l, out, false, m, ldo);
}

fn matmulAt(k: *const Kernels, s: cuda.Stream, x: u64, x_stride: usize, l: Linear, out: u64, f32_out: bool, m: usize, ldo: ?usize) !void {
    if (m < 1) return error.Invalid;
    const n: usize = l.n;
    const kk: usize = l.k;
    if (kk % 64 != 0 or l.npad < n) return error.Invalid;
    const sk = splitK(n, kk);
    const bm: usize = if (sk > 1 and m >= fused_rows) 0 else bucket(m);
    const md = k.mode;
    // Mode.fuse: a split shape below FUSED_ROWS on the fused form (its K slices added in slice order by one block):
    // row tile 64 on the prompt's fused kernel, 16 and 32 on the decode instantiations
    const fuse_ok = sk > 1 and md.fuse != 0 and n >= md.fuse_n;
    const fused64 = fuse_ok and bm == 64;
    const fused = bm == 0 or fused64;
    const small = !fused and fuse_ok and bm <= 32;
    const cluster = !fused and !small and sk > 1 and sk <= 8 and k.major >= 9;
    // sm_89 and older would add slices in the reduce (part + reduce_kernel): never on GB10, not ported
    if (!fused and !small and sk > 1 and !cluster) return error.SplitWithoutCluster;
    const tile: usize = if (fused) 64 else bm;
    const rows_t = (m + tile - 1) / tile;
    const ci = @intFromBool(cluster);
    const fi = @intFromBool(f32_out);
    const bi = bucketIndex(bm);
    const stages: usize = if (small) md.fuse else 4;
    const deep = @intFromBool(md.fuse == 8);
    const f = if (ldo != null) (if (fused) k.ld_fused else if (small) k.ld_fuse_s[deep][bi] else k.ld_tiled[ci][bi]) else if (fused) k.fused[fi] else if (small) k.fuse_s[deep][fi][bi] else k.tiled[fi][ci][bi];
    const sk_arg: usize = if ((small or fused64) and md.mutant) sk / 2 else sk;
    var a: cuda.Args = .{};
    a.add(x);
    a.add(l.w8);
    a.add(l.bs);
    a.add(@as(f32, 1.0));
    a.add(out);
    a.add(@as(u64, 0));
    for ([_]usize{ m, n, kk, sk_arg, l.npad, if (m == 1) kk else x_stride, l2Group(rows_t, tile, kk) }) |v| a.add(@as(c_int, @intCast(v)));
    if (ldo) |ld| a.add(@as(c_int, @intCast(ld)));
    const z: u32 = if (fused or small) 1 else @intCast(sk);
    try cuda.launch.launch(f, .{
        .grid = .{ .x = @intCast(rows_t * ((n + 63) / 64)), .y = 1, .z = z },
        .block = .{ .x = 128 },
        .shared = smemS(tile, stages),
        .cluster = if (cluster) .{ .x = 1, .y = 1, .z = @intCast(sk) } else null,
    }, s, &a);
}

// ---- host layouts (Fp8BlockLinear.from_checkpoint) ------------------------------------------------------------------

/// Fp8BlockLinear.column_scales: fp32 `scale_inv` [ceil(n/128), k/128] -> `out` [n, k/64], each (row, 64 inputs)'s
/// block scale.
pub fn columnScales(scale_inv: []const f32, n: usize, k: usize, out: []f32) !void {
    if (k % 128 != 0 or scale_inv.len != ((n + 127) / 128) * (k / 128) or out.len != n * (k / 64)) return error.BadScaleShape;
    const kb = k / 128;
    for (0..n) |r| for (0..k / 64) |j| {
        out[r * (k / 64) + j] = scale_inv[(r / 128) * kb + j / 2];
    };
}

/// The input offset within a 32-input step of fragment byte `byte` of lane `lane` (fragment_index's `kin`).
pub fn kin(lane: usize, byte: usize) usize {
    return 16 * (byte / 4) + 2 * (lane % 4) + (byte % 2) + 8 * ((byte % 4) / 2);
}

/// _fragment_order: e4m3 bytes [n, k] (rows past n zero up to npad) -> [npad/64][k/64][8][32][2][8].
pub fn fragmentOrder(codes: []const u8, n: usize, k: usize, npad: usize, out: []u8) !void {
    if (k % 64 != 0 or npad % 64 != 0 or npad < n or codes.len != n * k or out.len != npad * k) return error.BadFp8Shape;
    var i: usize = 0;
    for (0..npad / 64) |a| for (0..k / 64) |b| for (0..8) |c| for (0..32) |lane| for (0..2) |h| for (0..8) |byte| {
        const row = a * 64 + c * 8 + lane / 4;
        const col = b * 64 + h * 32 + kin(lane, byte);
        out[i] = if (row < n) codes[row * k + col] else 0;
        i += 1;
    };
}

/// from_rows' bs: fp32 column scales [n, k/64] (ones for rows past n up to npad) -> [npad/64][k/64][64].
pub fn tileScales(cols: []const f32, n: usize, k: usize, npad: usize, out: []f32) !void {
    const kg = k / 64;
    if (k % 64 != 0 or npad % 64 != 0 or npad < n or cols.len != n * kg or out.len != npad * kg) return error.BadFp8Shape;
    for (0..npad / 64) |a| for (0..kg) |g| for (0..64) |r| {
        const row = a * 64 + r;
        out[(a * kg + g) * 64 + r] = if (row < n) cols[row * kg + g] else 1.0;
    };
}

test "split_k, buckets and shared memory follow qmm.py and qmmf.cu" {
    // the INT4-AutoRound checkpoint's block-FP8 shapes, one GPU and a TP=2 rank
    try std.testing.expectEqual(@as(usize, 1), splitK(16384, 2560));
    try std.testing.expectEqual(@as(usize, 1), splitK(13312, 2560));
    try std.testing.expectEqual(@as(usize, 8), splitK(2560, 6144));
    try std.testing.expectEqual(@as(usize, 4), splitK(2560, 2560));
    try std.testing.expectEqual(@as(usize, 2), splitK(2560, 1280));
    try std.testing.expectEqual(@as(usize, 4), splitK(2560, 3072));
    try std.testing.expectEqual(@as(usize, 1), splitK(2560, 640));
    try std.testing.expectEqual(@as(usize, 4), splitK(1280, 2560));
    try std.testing.expectEqual(@as(usize, 25600), smem(16));
    try std.testing.expectEqual(@as(usize, 33792), smem(32));
    try std.testing.expectEqual(@as(usize, 50176), smem(64));
    try std.testing.expectEqual(@as(usize, 13312), npadOf(13312));
    try std.testing.expectEqual(@as(usize, 128), npadOf(96));
    try std.testing.expectEqual(@as(usize, 64), bucket(33));
    try std.testing.expectEqual(@as(usize, 1), l2Group(1, 16, 2560));
    try std.testing.expectEqual(@as(usize, 38), l2Group(64, 64, 2560));
    try std.testing.expectEqualStrings("_ZN10tf_fn_qmmf11qmmf_kernelILi3ELi32ELi64ELi1ELi4ELi4ELb1ELb1ELb0EEEvPK13__nv_bfloat16PKhS5_fPvPfiiiiiii", sym.tiled[1][1][1]);
    try std.testing.expectEqualStrings("_ZN10tf_fn_qmmf11qmmf_kernelILi3ELi64ELi64ELi1ELi4ELi4ELb0ELb0ELb1EEEvPK13__nv_bfloat16PKhS5_fPvPfiiiiiii", sym.fused[0]);
}

test "fragment order is fragment_index's (k, n) of every byte" {
    // fragment_index: p = 16 (byte / 4) + 4 (lane % 4) + byte % 4; kin = 16 (p / 16) + 2 ((p % 16) / 4) + p % 2 + 8 ((p % 4) / 2)
    for (0..32) |lane| for (0..8) |byte| {
        const p = 16 * (byte / 4) + 4 * (lane % 4) + (byte % 4);
        try std.testing.expectEqual(16 * (p / 16) + 2 * ((p % 16) / 4) + (p % 2) + 8 * ((p % 4) / 2), kin(lane, byte));
    };
    // each 32-input step's lane bytes cover 32 inputs of 8 rows once (a permutation)
    for (0..4) |q| {
        var seen: [32]bool = @splat(false);
        for (0..8) |byte| {
            const v = kin(q, byte);
            try std.testing.expect(!seen[v]);
            seen[v] = true;
        }
        for (0..8) |byte| try std.testing.expectEqual(kin(q, byte), kin(q + 4 * 5, byte));
    }
    // hand cases: lane 0 byte 0 -> 0, byte 1 -> 1, byte 2 -> 8, byte 3 -> 9, byte 4 -> 16; lane 1 byte 0 -> 2
    try std.testing.expectEqual(@as(usize, 0), kin(0, 0));
    try std.testing.expectEqual(@as(usize, 1), kin(0, 1));
    try std.testing.expectEqual(@as(usize, 8), kin(0, 2));
    try std.testing.expectEqual(@as(usize, 9), kin(0, 3));
    try std.testing.expectEqual(@as(usize, 16), kin(0, 4));
    try std.testing.expectEqual(@as(usize, 2), kin(1, 0));
    try std.testing.expectEqual(@as(usize, 31), kin(7, 7)); // quad 3, byte 7: 16 + 6 + 1 + 8
}

test "fragment order and tile scales on a small matrix" {
    const gpa = std.testing.allocator;
    const n = 70;
    const k = 128;
    const npad = npadOf(n);
    const codes = try gpa.alloc(u8, n * k);
    defer gpa.free(codes);
    for (codes, 0..) |*c, i| c.* = @intCast((i * 7 + 3) % 251);
    const out = try gpa.alloc(u8, npad * k);
    defer gpa.free(out);
    try fragmentOrder(codes, n, k, npad, out);
    // byte (a, b, c, lane, h, byte) at ((((a * kg + b) * 8 + c) * 32 + lane) * 2 + h) * 8 + byte
    const at = struct {
        fn f(a: usize, b: usize, c: usize, lane: usize, h: usize, byte: usize) usize {
            return ((((a * (k / 64) + b) * 8 + c) * 32 + lane) * 2 + h) * 8 + byte;
        }
    }.f;
    try std.testing.expectEqual(codes[0], out[at(0, 0, 0, 0, 0, 0)]);
    try std.testing.expectEqual(codes[1 * k + 64 + 32 + 9], out[at(0, 1, 0, 4, 1, 3)]); // row 1, col 64 + 32 + kin(4, 3) = 9
    try std.testing.expectEqual(codes[69 * k + 0], out[at(1, 0, 0, 20, 0, 0)]); // row 64 + 5 = 69, lane 20: quad 0, kin 0
    try std.testing.expectEqual(@as(u8, 0), out[at(1, 0, 0, 24, 0, 0)]); // row 70: padding
    var inv = [_]f32{ 0.5, 2.0 }; // [ceil(70/128) = 1, 128/128 = 1] ... one block row, one block column
    var cols: [n * 2]f32 = undefined;
    try std.testing.expectError(error.BadScaleShape, columnScales(&inv, n, k, &cols));
    try columnScales(inv[0..1], n, k, &cols);
    for (cols) |v| try std.testing.expectEqual(@as(f32, 0.5), v);
    cols[69 * 2 + 1] = 3;
    var bs: [128 * 2]f32 = undefined;
    try tileScales(&cols, n, k, npad, &bs);
    try std.testing.expectEqual(@as(f32, 3), bs[(1 * 2 + 1) * 64 + 5]);
    try std.testing.expectEqual(@as(f32, 1), bs[(1 * 2 + 0) * 64 + 6]); // row 70: padding scales are one
    try std.testing.expectEqual(@as(f32, 0.5), bs[(0 * 2 + 1) * 64 + 63]);
}

test "column scales repeat 128 rows and two 64-input groups" {
    var inv = [_]f32{ 1, 2, 3, 4, 5, 6 }; // [2, 3]: n 200 -> 2 block rows, k 384 -> 3 block columns
    var cols: [200 * 6]f32 = undefined;
    try columnScales(&inv, 200, 384, &cols);
    try std.testing.expectEqual(@as(f32, 1), cols[0]);
    try std.testing.expectEqual(@as(f32, 1), cols[1]);
    try std.testing.expectEqual(@as(f32, 2), cols[2]);
    try std.testing.expectEqual(@as(f32, 3), cols[127 * 6 + 5]);
    try std.testing.expectEqual(@as(f32, 4), cols[128 * 6 + 0]);
    try std.testing.expectEqual(@as(f32, 6), cols[199 * 6 + 4]);
}

// ---- fp8-check: the port against Python's Fp8BlockLinear (tools/zig/check_fp8block.py's cases) ---------------------

fn readFile(gpa: std.mem.Allocator, io: std.Io, dir: []const u8, name: []const u8, suffix: []const u8) ![]u8 {
    const path = try std.fmt.allocPrint(gpa, "{s}/{s}{s}", .{ dir, name, suffix });
    defer gpa.free(path);
    return std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 31));
}

fn hex(bytes: []const u8) [64]u8 {
    var sum: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &sum, .{});
    return std.fmt.bytesToHex(sum, .lower);
}

/// Every case of `dir` (cases.json + each case's codes, scale_inv and input rows): the host layouts' sha256 against
/// Python's, then `matmul` at every row count (bf16, and fp32 where Python wrote it) against Python's outputs, a
/// row's bits against its one-row call, and the time at 1 and 4096 rows. True when every byte agrees.
pub fn check(gpa: std.mem.Allocator, io: std.Io, ctx: *const cuda.Context, dir: []const u8) !bool {
    const d = ctx.d;
    var k = try Kernels.load(ctx);
    defer k.deinit();
    var stream = try cuda.Stream.init(d, true);
    defer stream.deinit();
    const text = try readFile(gpa, io, dir, "cases", ".json");
    defer gpa.free(text);
    const parsed = try std.json.parseFromSlice(std.json.Value, gpa, text, .{});
    defer parsed.deinit();
    var ok = true;
    var e0 = try cuda.Event.init(d, true);
    defer e0.deinit();
    var e1 = try cuda.Event.init(d, true);
    defer e1.deinit();
    for (parsed.value.object.get("cases").?.array.items) |cv| {
        const c = cv.object;
        const name = c.get("name").?.string;
        const n: usize = @intCast(c.get("n").?.integer);
        const kk: usize = @intCast(c.get("k").?.integer);
        const npad = npadOf(n);
        const codes = try readFile(gpa, io, dir, name, "_codes.bin");
        defer gpa.free(codes);
        const inv_b = try readFile(gpa, io, dir, name, "_inv.bin");
        defer gpa.free(inv_b);
        const xb = try readFile(gpa, io, dir, name, "_x.bin");
        defer gpa.free(xb);
        const inv = try gpa.alloc(f32, inv_b.len / 4);
        defer gpa.free(inv);
        @memcpy(std.mem.sliceAsBytes(inv), inv_b);
        // the layouts
        const cols = try gpa.alloc(f32, n * (kk / 64));
        defer gpa.free(cols);
        try columnScales(inv, n, kk, cols);
        const bs = try gpa.alloc(f32, npad * (kk / 64));
        defer gpa.free(bs);
        try tileScales(cols, n, kk, npad, bs);
        const w8 = try gpa.alloc(u8, npad * kk);
        defer gpa.free(w8);
        try fragmentOrder(codes, n, kk, npad, w8);
        const w8_ok = std.mem.eql(u8, &hex(w8), c.get("w8").?.string);
        const bs_ok = std.mem.eql(u8, &hex(std.mem.sliceAsBytes(bs)), c.get("bs").?.string);
        ok = ok and w8_ok and bs_ok;
        var dw = try cuda.DeviceBuffer.fromHost(d, w8);
        defer dw.free();
        var dbs = try cuda.DeviceBuffer.fromHost(d, std.mem.sliceAsBytes(bs));
        defer dbs.free();
        var dx = try cuda.DeviceBuffer.fromHost(d, xb);
        defer dx.free();
        const max_m = xb.len / (2 * kk);
        var dy = try cuda.DeviceBuffer.alloc(d, max_m * n * 4);
        defer dy.free();
        var dy1 = try cuda.DeviceBuffer.alloc(d, n * 4);
        defer dy1.free();
        const host = try gpa.alloc(u8, max_m * n * 4);
        defer gpa.free(host);
        const one = try gpa.alloc(u8, n * 4);
        defer gpa.free(one);
        const l: Linear = .{ .w8 = dw.ptr, .bs = dbs.ptr, .n = @intCast(n), .k = @intCast(kk), .npad = @intCast(npad) };
        var equal: usize = 0;
        var total: usize = 0;
        var inv_ok = true;
        for ([_][]const u8{ "bf16", "fp32" }) |kind| {
            const f32_out = kind[0] == 'f';
            const es: usize = if (f32_out) 4 else 2;
            var it = c.get(kind).?.object.iterator();
            while (it.next()) |kv| {
                const m = try std.fmt.parseInt(usize, kv.key_ptr.*, 10);
                try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, f32_out, m);
                try stream.synchronize();
                try dy.download(0, host[0 .. m * n * es]);
                total += 1;
                if (std.mem.eql(u8, &hex(host[0 .. m * n * es]), kv.value_ptr.string)) {
                    equal += 1;
                } else {
                    ok = false;
                    std.debug.print("  {s} {s} m {d}: DIFFER\n", .{ name, kind, m });
                }
                // row invariance: rows of this call against one-row calls
                if (m == max_m or m == 300) for ([_]usize{ 0, 1, m / 2, m - 1 }) |r| {
                    try matmul(&k, stream, dx.ptr + r * kk * 2, kk, l, dy1.ptr, f32_out, 1);
                    try stream.synchronize();
                    try dy1.download(0, one[0 .. n * es]);
                    if (!std.mem.eql(u8, one[0 .. n * es], host[r * n * es ..][0 .. n * es])) {
                        inv_ok = false;
                        std.debug.print("  {s} {s} m {d} row {d}: differs from its one-row call\n", .{ name, kind, m, r });
                    }
                };
            }
        }
        ok = ok and inv_ok;
        // matmulLd (fn_qmmf_ld): every bf16 row count's rows written `ldo` apart hold the contiguous call's bytes,
        // and the gaps between them stay untouched
        {
            const ldo = n + 72;
            var dl = try cuda.DeviceBuffer.alloc(d, max_m * ldo * 2);
            defer dl.free();
            const strided = try gpa.alloc(u8, max_m * ldo * 2);
            defer gpa.free(strided);
            var ld_ok = true;
            var ld_n: usize = 0;
            var it = c.get("bf16").?.object.iterator();
            while (it.next()) |kv| {
                const m = try std.fmt.parseInt(usize, kv.key_ptr.*, 10);
                @memset(strided, 0xAB);
                try dl.upload(0, strided);
                try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, false, m);
                try matmulLd(&k, stream, dx.ptr, kk, l, dl.ptr, ldo, m);
                try stream.synchronize();
                try dy.download(0, host[0 .. m * n * 2]);
                try dl.download(0, strided[0 .. m * ldo * 2]);
                ld_n += 1;
                for (0..m) |r| {
                    const row = strided[r * ldo * 2 ..][0 .. ldo * 2];
                    if (!std.mem.eql(u8, row[0 .. n * 2], host[r * n * 2 ..][0 .. n * 2]) or !std.mem.allEqual(u8, row[n * 2 ..], 0xAB)) {
                        ld_ok = false;
                        std.debug.print("  {s} bf16 m {d} row {d}: matmulLd differs from matmul (or wrote past its columns)\n", .{ name, m, r });
                        break;
                    }
                }
            }
            std.debug.print("  {s}: matmulLd (rows {d} apart) {s} matmul at {d} row counts\n", .{ name, ldo, if (ld_ok) "byte-equal to" else "DIFFERS from", ld_n });
            ok = ok and ld_ok;
        }
        // time at 1 and max_m rows (bf16 out)
        var us: [2]f64 = undefined;
        for ([_]usize{ 1, max_m }, 0..) |m, i| {
            const reps: usize = if (m == 1) 200 else 20;
            try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, false, m);
            try e0.record(stream);
            for (0..reps) |_| try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, false, m);
            try e1.record(stream);
            try e1.synchronize();
            us[i] = @as(f64, try cuda.Event.elapsedMs(e0, e1)) * 1000.0 / @as(f64, @floatFromInt(reps));
        }
        const wbytes: f64 = @floatFromInt(npad * kk + npad * (kk / 64) * 4);
        const flops: f64 = 2.0 * @as(f64, @floatFromInt(max_m * n * kk));
        std.debug.print("{s} {s}: n {d} k {d} split_k {d}: layouts w8 {s} bs {s}, outputs {d}/{d} equal, rows {s} one-row calls; 1 row {d:.1} us ({d:.0} GB/s weights), {d} rows {d:.0} us ({d:.1} TFLOP/s)\n", .{
            if (w8_ok and bs_ok and equal == total and inv_ok) "PASS" else "FAIL", name, n, kk, splitK(n, kk),
            if (w8_ok) "equal" else "DIFFER", if (bs_ok) "equal" else "DIFFER", equal, total, if (inv_ok) "equal" else "DIFFER",
            us[0], wbytes / us[0] / 1000.0, max_m, us[1], flops / us[1] / 1e6,
        });
    }
    return ok;
}

// ---- `fp8-fused-check`: the fused split-K decode tiles (Mode.fuse) against the cluster kernel ----------------------

const fused_modes = [_]struct { name: []const u8, m: Mode }{
    .{ .name = "cluster", .m = .{} },
    .{ .name = "fused4", .m = .{ .fuse = 4 } },
    .{ .name = "fused8", .m = .{ .fuse = 8 } },
};

/// Random block-FP8 weights at the checkpoint's decode shapes (no NaN codes, scales 2^-9..2^-4): each fused depth's
/// outputs (bf16 and fp32; the ld form for the projections, its gaps poisoned) byte-compared with the cluster
/// kernel's at decode row counts, the output poisoned before every call; a mutant (the fused form told half the
/// slices) must differ; then each mode's time at 1-64 rows, the weights rotated over copies that do not fit the 24 MB
/// L2 (the engine reads each layer's weights once a round), modes interleaved, median of 5.
pub fn fusedCheck(gpa: std.mem.Allocator, ctx: *const cuda.Context) !bool {
    const d = ctx.d;
    var k = try Kernels.load(ctx);
    defer k.deinit();
    var stream = try cuda.Stream.init(d, true);
    defer stream.deinit();
    var e0 = try cuda.Event.init(d, true);
    defer e0.deinit();
    var e1 = try cuda.Event.init(d, true);
    defer e1.deinit();
    var prng = std.Random.DefaultPrng.init(808);
    const r = prng.random();
    var ok = true;
    const Shape = struct { n: usize, k: usize, ld: bool };
    const shapes = [_]Shape{
        .{ .n = 2560, .k = 6144, .ld = false }, .{ .n = 2560, .k = 3072, .ld = false },  .{ .n = 2560, .k = 2560, .ld = false },
        .{ .n = 2560, .k = 1280, .ld = false }, .{ .n = 16384, .k = 2560, .ld = true }, .{ .n = 13312, .k = 2560, .ld = true },
    };
    const rows_list = [_]usize{ 1, 2, 3, 5, 8, 13, 16, 17, 20, 31, 32, 33, 48, 64 };
    const max_m: usize = 64;
    for (shapes) |sh| {
        const n = sh.n;
        const kk = sh.k;
        const npad = npadOf(n);
        const sk = splitK(n, kk);
        // the weights
        const codes = try gpa.alloc(u8, n * kk);
        defer gpa.free(codes);
        r.bytes(codes);
        for (codes) |*c| if ((c.* & 0x7F) == 0x7F) {
            c.* ^= 0x01;
        };
        const inv = try gpa.alloc(f32, ((n + 127) / 128) * (kk / 128));
        defer gpa.free(inv);
        for (inv) |*v| v.* = std.math.ldexp(1.0 + r.float(f32), -9 + @as(i32, r.intRangeLessThan(i32, 0, 5)));
        const cols = try gpa.alloc(f32, n * (kk / 64));
        defer gpa.free(cols);
        try columnScales(inv, n, kk, cols);
        const bs = try gpa.alloc(f32, npad * (kk / 64));
        defer gpa.free(bs);
        try tileScales(cols, n, kk, npad, bs);
        const w8 = try gpa.alloc(u8, npad * kk);
        defer gpa.free(w8);
        try fragmentOrder(codes, n, kk, npad, w8);
        const wbytes = npad * kk + npad * (kk / 64) * 4;
        const copies = @max(2, (96 << 20) / wbytes + 1);
        var dws: [16]cuda.DeviceBuffer = undefined;
        var dbs: [16]cuda.DeviceBuffer = undefined;
        const nc = @min(copies, 16);
        for (0..nc) |i| {
            dws[i] = try cuda.DeviceBuffer.fromHost(d, w8);
            dbs[i] = try cuda.DeviceBuffer.fromHost(d, std.mem.sliceAsBytes(bs));
        }
        defer for (0..nc) |i| {
            dws[i].free();
            dbs[i].free();
        };
        const xh = try gpa.alloc(u16, max_m * kk);
        defer gpa.free(xh);
        for (xh) |*v| {
            const f: f32 = r.floatNorm(f32);
            v.* = @intCast(@as(u32, @bitCast(f)) >> 16);
        }
        var dx = try cuda.DeviceBuffer.fromHost(d, std.mem.sliceAsBytes(xh));
        defer dx.free();
        const ldo = n + 72;
        const out_len = max_m * @max(n * 4, ldo * 2);
        var dy = try cuda.DeviceBuffer.alloc(d, out_len);
        defer dy.free();
        const ref = try gpa.alloc(u8, out_len);
        defer gpa.free(ref);
        const got = try gpa.alloc(u8, out_len);
        defer gpa.free(got);
        const lin: Linear = .{ .w8 = dws[0].ptr, .bs = dbs[0].ptr, .n = @intCast(n), .k = @intCast(kk), .npad = @intCast(npad) };
        // bytes: each mode (and the mutant) against the cluster kernel; kinds 0 bf16, 1 fp32, 2 ld (bf16 rows ldo apart)
        var calls: usize = 0;
        var differ: usize = 0;
        var mutant_differ: [3]usize = .{ 0, 0, 0 };
        var mutant_calls: [3]usize = .{ 0, 0, 0 };
        for (rows_list) |m| for (0..3) |kind| {
            if (kind == 2 and !sh.ld) continue;
            if (kind != 2 and sh.ld and kind == 1) continue;
            const len = if (kind == 2) m * ldo * 2 else m * n * @as(usize, if (kind == 1) 4 else 2);
            const run = struct {
                fn f(kp: *const Kernels, st: cuda.Stream, y: cuda.DeviceBuffer, xp: u64, l: Linear, kd: usize, mm: usize, ld: usize, all: usize) !void {
                    try y.fill8(0xA5, st.handle);
                    _ = all;
                    if (kd == 2) try matmulLd(kp, st, xp, l.k, l, y.ptr, ld, mm) else try matmul(kp, st, xp, l.k, l, y.ptr, kd == 1, mm);
                    try st.synchronize();
                }
            }.f;
            k.mode = .{};
            try run(&k, stream, dy, dx.ptr, lin, kind, m, ldo, out_len);
            // the whole poisoned buffer, past the m rows (and the ld form's gaps between rows) included: a write
            // outside a call's rows and columns, by any path, is a difference; the cluster kernel's own bounds too
            try dy.download(0, ref[0..out_len]);
            var outside = !std.mem.allEqual(u8, ref[len..out_len], 0xA5);
            if (kind == 2) for (0..m) |row| {
                if (!std.mem.allEqual(u8, ref[row * ldo * 2 + n * 2 .. (row + 1) * ldo * 2], 0xA5)) outside = true;
            };
            if (outside) {
                ok = false;
                std.debug.print("  n {d} k {d} m {d} kind {d}: the cluster kernel wrote outside its rows or columns\n", .{ n, kk, m, kind });
            }
            for (fused_modes[1..]) |wm| {
                k.mode = wm.m;
                try run(&k, stream, dy, dx.ptr, lin, kind, m, ldo, out_len);
                try dy.download(0, got[0..out_len]);
                calls += 1;
                if (!std.mem.eql(u8, ref[0..out_len], got[0..out_len])) {
                    differ += 1;
                    ok = false;
                    std.debug.print("  n {d} k {d} m {d} kind {d} mode {s}: DIFFERS from the cluster kernel ({s})\n", .{ n, kk, m, kind, wm.name, if (std.mem.eql(u8, ref[0..len], got[0..len])) "outside the call's rows" else "in the rows" });
                }
            }
            if (sk > 1) {
                k.mode = .{ .fuse = 8, .mutant = true };
                try run(&k, stream, dy, dx.ptr, lin, kind, m, ldo, out_len);
                try dy.download(0, got[0..out_len]);
                const bi = bucketIndex(bucket(m));
                mutant_calls[bi] += 1;
                if (!std.mem.eql(u8, ref[0..out_len], got[0..out_len])) mutant_differ[bi] += 1;
            }
        };
        // the mutant is killed when every row tile's path (16, 32: the decode fused kernels, 64: the prompt's) shows it
        const mutant_ok = sk == 1 or (mutant_differ[0] > 0 and mutant_differ[1] > 0 and mutant_differ[2] > 0);
        if (!mutant_ok) ok = false;
        std.debug.print("{s} n {d} k {d} split_k {d}: {d} fused calls (rows {any}), {d} differ from the cluster kernel; mutant (fused, half the slices) differs on {d}/{d} (tile 16), {d}/{d} (32), {d}/{d} (64) calls: {s}\n", .{ if (differ == 0 and mutant_ok) "PASS" else "FAIL", n, kk, sk, calls, rows_list, differ, mutant_differ[0], mutant_calls[0], mutant_differ[1], mutant_calls[1], mutant_differ[2], mutant_calls[2], if (sk == 1) "no split" else if (mutant_ok) "KILLED" else "SURVIVED (the check cannot see a slice change)" });
        // speed
        for ([_]usize{ 1, 4, 16, 17, 32, 33, 64 }) |m| {
            var t: [fused_modes.len][5]f64 = undefined;
            const reps: usize = 48;
            for (0..5) |rep| for (fused_modes, 0..) |wm, mi| {
                k.mode = wm.m;
                var l = lin;
                if (sh.ld) try matmulLd(&k, stream, dx.ptr, kk, l, dy.ptr, ldo, m) else try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, false, m);
                try e0.record(stream);
                for (0..reps) |i| {
                    l.w8 = dws[(i + 1) % nc].ptr;
                    l.bs = dbs[(i + 1) % nc].ptr;
                    if (sh.ld) try matmulLd(&k, stream, dx.ptr, kk, l, dy.ptr, ldo, m) else try matmul(&k, stream, dx.ptr, kk, l, dy.ptr, false, m);
                }
                try e1.record(stream);
                try e1.synchronize();
                t[mi][rep] = @as(f64, try cuda.Event.elapsedMs(e0, e1)) * 1000.0 / @as(f64, @floatFromInt(reps));
            };
            std.debug.print("  n {d} k {d} m {d}:", .{ n, kk, m });
            for (&t, fused_modes) |*a, wm| {
                std.mem.sort(f64, a, {}, std.sort.asc(f64));
                std.debug.print(" {s} {d:.1} us [{d:.1}-{d:.1}] {d:.0} GB/s;", .{ wm.name, a[2], a[0], a[4], @as(f64, @floatFromInt(wbytes)) / a[2] / 1e3 });
            }
            std.debug.print("\n", .{});
        }
    }
    k.mode = .{};
    return ok;
}
