//! `draft-check` (no checkpoint): the batched greedy draft draw (cuda_torch_ops.Torch.draftGreedyRows, one
//! block a row) against the per-row path it replaces (draftGreedy: toF32, logsumexp, argmax, draftPick over one row
//! copied alone), bytes compared over the draft vocabulary's width and the main head's, several row counts and
//! adversarial rows (ties, NaN, +-inf, signed zeros, subnormals, wide exponents); then both timed.
const std = @import("std");
const cuda = @import("cuda");
const tops = @import("cuda_torch_ops.zig");

pub const widths = [_]usize{ 79591, 248320, 4096, 1000, 131 };
pub const default_rows = [_]usize{ 1, 2, 3, 4, 5, 8, 16, 64 };

const Fill = enum { normal, wide, ties, nan, inf, neg_inf, zeros, subnormal, mixed };
const fills = [_]Fill{ .normal, .wide, .ties, .nan, .inf, .neg_inf, .zeros, .subnormal, .mixed };

fn bf16Bits(v: f32) u16 {
    return @truncate(@as(u32, @bitCast(v)) >> 16);
}

/// `rows` rows of `n` bf16 values: the fill's shape, every row different (its own maximum column).
fn fill(h: []u16, rows: usize, n: usize, r: std.Random, how: Fill) void {
    for (0..rows) |row| {
        const x = h[row * n ..][0..n];
        for (x) |*v| v.* = switch (how) {
            .normal, .nan, .inf, .neg_inf, .zeros, .ties, .mixed => bf16Bits(@floatCast(r.floatNorm(f64) * 3.0)),
            .wide => bf16Bits((if (r.boolean()) @as(f32, -1) else 1) * std.math.ldexp(1.0 + r.float(f32), r.intRangeAtMost(i32, -30, 30))),
            .subnormal => @as(u16, @intCast(r.uintLessThan(u32, 0x80))) | (if (r.boolean()) @as(u16, 0x8000) else 0),
        };
        switch (how) {
            .ties => {
                // the maximum at several columns, the first of them the pick
                const top = bf16Bits(9.5);
                for (0..5) |_| x[r.uintLessThan(usize, n)] = top;
            },
            .nan => x[r.uintLessThan(usize, n)] = 0x7fc0 | @as(u16, @intCast(r.uintLessThan(u32, 0x3f))),
            .inf => x[r.uintLessThan(usize, n)] = 0x7f80,
            .neg_inf => for (x) |*v| {
                v.* = 0xff80;
            },
            .zeros => {
                // the row's maximum is zero, both signs present
                for (x) |*v| v.* = bf16Bits(-@abs(@as(f32, @floatCast(r.floatNorm(f64)))) - 1.0);
                x[r.uintLessThan(usize, n)] = 0x8000;
                x[r.uintLessThan(usize, n)] = 0x0000;
            },
            .mixed => {
                x[r.uintLessThan(usize, n)] = 0xff80;
                x[r.uintLessThan(usize, n)] = 0x0001;
                x[r.uintLessThan(usize, n)] = bf16Bits(80.0);
            },
            else => {},
        }
    }
}

pub fn check(gpa: std.mem.Allocator, d: *const cuda.Driver, th: tops.Torch, rows_list: []const usize) !bool {
    var prng = std.Random.DefaultPrng.init(0x4e71_a1d4);
    const r = prng.random();
    var all = true;
    var max_rows: usize = 0;
    for (rows_list) |m| max_rows = @max(max_rows, m);
    for (widths) |n| {
        const sz = try tops.Torch.Sample.bytes(th.f, 1, n, 1);
        var scratch: [7]cuda.DeviceBuffer = undefined;
        var taken: usize = 0;
        defer for (scratch[0..taken]) |*b| b.free();
        var s: tops.Torch.Sample = undefined;
        inline for (.{ "f32", "vals", "idx", "topk", "lse", "lse_scratch", "col" }, 0..) |name, i| {
            scratch[i] = try cuda.DeviceBuffer.alloc(d, @max(sz[i], 256));
            taken += 1;
            @field(s, name) = scratch[i].ptr;
        }
        var x = try cuda.DeviceBuffer.alloc(d, max_rows * n * 2);
        defer x.free();
        var o1 = try cuda.DeviceBuffer.alloc(d, max_rows * 3 * 4);
        defer o1.free();
        var o2 = try cuda.DeviceBuffer.alloc(d, max_rows * 3 * 4);
        defer o2.free();
        const h = try gpa.alloc(u16, max_rows * n);
        defer gpa.free(h);
        const h1 = try gpa.alloc(f32, max_rows * 3);
        defer gpa.free(h1);
        const h2 = try gpa.alloc(f32, max_rows * 3);
        defer gpa.free(h2);
        for (fills) |how| {
            fill(h, max_rows, n, r, how);
            try x.upload(0, std.mem.sliceAsBytes(h));
            for (rows_list) |m| {
                try o1.fill8(0xA5, th.s.handle);
                try o2.fill8(0x5A, th.s.handle);
                // the old way: each row copied alone (draftGreedy's toF32 at offset 0), its [max, lse, col]
                for (0..m) |row| try th.draftGreedy(x.ptr + row * n * 2, n, s, o1.ptr + row * 12);
                try th.draftGreedyRows(x.ptr, m, n, o2.ptr);
                try th.s.synchronize();
                try o1.download(0, std.mem.sliceAsBytes(h1[0 .. m * 3]));
                try o2.download(0, std.mem.sliceAsBytes(h2[0 .. m * 3]));
                var differ: usize = 0;
                var first: ?usize = null;
                for (0..m * 3) |i| if (@as(u32, @bitCast(h1[i])) != @as(u32, @bitCast(h2[i]))) {
                    differ += 1;
                    if (first == null) first = i;
                };
                if (differ != 0) all = false;
                std.debug.print("{s} draft greedy rows N {d} {s} rows {d}", .{ if (differ == 0) "EQUAL" else "DIFFER", n, @tagName(how), m });
                if (first) |f0| std.debug.print(": {d} of {d} values differ, first row {d} field {d}: {x:0>8} vs {x:0>8}", .{ differ, m * 3, f0 / 3, f0 % 3, @as(u32, @bitCast(h1[f0])), @as(u32, @bitCast(h2[f0])) });
                std.debug.print("\n", .{});
            }
        }
    }
    return all;
}

/// Mean microseconds of `rows` greedy draws the old way (one row's four launches each, one wait at the end) and
/// batched (one launch), `reps` each, over the draft vocabulary's width.
pub fn bench(gpa: std.mem.Allocator, d: *const cuda.Driver, th: tops.Torch, rows_list: []const usize, reps: usize) !void {
    var prng = std.Random.DefaultPrng.init(7);
    const r = prng.random();
    const n = widths[0];
    var max_rows: usize = 0;
    for (rows_list) |m| max_rows = @max(max_rows, m);
    const sz = try tops.Torch.Sample.bytes(th.f, 1, n, 1);
    var scratch: [7]cuda.DeviceBuffer = undefined;
    var taken: usize = 0;
    defer for (scratch[0..taken]) |*b| b.free();
    var s: tops.Torch.Sample = undefined;
    inline for (.{ "f32", "vals", "idx", "topk", "lse", "lse_scratch", "col" }, 0..) |name, i| {
        scratch[i] = try cuda.DeviceBuffer.alloc(d, @max(sz[i], 256));
        taken += 1;
        @field(s, name) = scratch[i].ptr;
    }
    var x = try cuda.DeviceBuffer.alloc(d, max_rows * n * 2);
    defer x.free();
    var o = try cuda.DeviceBuffer.alloc(d, max_rows * 3 * 4);
    defer o.free();
    const h = try gpa.alloc(u16, max_rows * n);
    defer gpa.free(h);
    fill(h, max_rows, n, r, .normal);
    try x.upload(0, std.mem.sliceAsBytes(h));
    var e0 = try cuda.Event.init(d, true);
    defer e0.deinit();
    var e1 = try cuda.Event.init(d, true);
    defer e1.deinit();
    for (rows_list) |m| {
        var us: [2]f64 = undefined;
        for (0..2) |which| {
            for (0..3) |_| if (which == 0) {
                for (0..m) |row| try th.draftGreedy(x.ptr + row * n * 2, n, s, o.ptr + row * 12);
            } else try th.draftGreedyRows(x.ptr, m, n, o.ptr);
            try e0.record(th.s);
            for (0..reps) |_| if (which == 0) {
                for (0..m) |row| try th.draftGreedy(x.ptr + row * n * 2, n, s, o.ptr + row * 12);
            } else try th.draftGreedyRows(x.ptr, m, n, o.ptr);
            try e1.record(th.s);
            try e1.synchronize();
            us[which] = @as(f64, try cuda.Event.elapsedMs(e0, e1)) * 1000.0 / @as(f64, @floatFromInt(reps));
        }
        std.debug.print("draft greedy N {d} rows {d}: a row at a time {d:.1} us, one launch {d:.1} us ({d:.2}x)\n", .{ n, m, us[0], us[1], us[0] / us[1] });
    }
}
