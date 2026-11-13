//! TF_FLASHNEXT_KERNEL_LOG=1: every launch is waited for and booked to its kernel and grid width. A gap of more
//! than 300 ms between launches closes a window and prints its table, so one decode request's kernels can be read
//! against the rounds its reply took. The waiting makes the run slower: its tok/s is not a speed result.
const std = @import("std");
const abi = @import("abi.zig");
const module = @import("module.zig");
const stream_ = @import("stream.zig");

const max = 4096;
const name_max = 96;
const gap_ns: u64 = 300 * std.time.ns_per_ms;

var known = false;
var enabled = false;
var handles: [max]abi.Function = @splat(null);
var grids: [max]u32 = @splat(0);
var ns: [max]u64 = @splat(0);
var calls: [max]u64 = @splat(0);
var used: usize = 0;

var name_handles: [max]abi.Function = @splat(null);
var name_bytes: [max][name_max]u8 = undefined;
var name_len: [max]usize = @splat(0);
var named: usize = 0;

var window_start: u64 = 0;
var last_end: u64 = 0;

pub fn on() bool {
    if (!known) {
        known = true;
        const v = std.c.getenv("TF_FLASHNEXT_KERNEL_LOG");
        enabled = v != null and std.mem.eql(u8, std.mem.span(v.?), "1");
    }
    return enabled;
}
pub fn now() u64 {
    var ts: std.c.timespec = undefined;
    if (std.c.clock_gettime(std.c.CLOCK.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// The name a module resolved a function under, kept for the table (a later lookup of the same handle is ignored).
pub fn note(handle: abi.Function, name: []const u8) void {
    if (!on() or handle == null or named == max) return;
    for (name_handles[0..named]) |h| if (h == handle) return;
    const n = @min(name.len, name_max);
    @memcpy(name_bytes[named][0..n], name[0..n]);
    name_len[named] = n;
    name_handles[named] = handle;
    named += 1;
}

fn nameOf(handle: abi.Function) []const u8 {
    for (name_handles[0..named], 0..) |h, i| if (h == handle) return name_bytes[i][0..name_len[i]];
    return "(unnamed)";
}

/// The launch queued since `t0` is waited for and booked to its kernel and grid width.
pub fn booked(f: module.Function, stream: stream_.Stream, t0: u64, grid_x: u32) void {
    if (last_end != 0 and t0 > last_end + gap_ns) dump();
    if (window_start == 0) window_start = t0;
    _ = f.d.api.cuStreamSynchronize(stream.handle);
    const t1 = now();
    var i: usize = 0;
    while (i < used and (handles[i] != f.handle or grids[i] != grid_x)) i += 1;
    if (i == used) {
        if (used == max) return;
        handles[i] = f.handle;
        grids[i] = grid_x;
        used += 1;
    }
    ns[i] += t1 - t0;
    calls[i] += 1;
    last_end = t1;
}

/// The window's kernels by time, the largest first; the table then starts over.
pub fn dump() void {
    if (used == 0 or window_start == 0) return;
    const wall = last_end - window_start;
    var total: u64 = 0;
    var launches: u64 = 0;
    for (ns[0..used], calls[0..used]) |v, c| {
        total += v;
        launches += c;
    }
    std.debug.print("kernel log: window {d:.1} ms wall, {d:.1} ms in kernels, {d} launches in {d} kernels\n", .{
        @as(f64, @floatFromInt(wall)) / 1e6, @as(f64, @floatFromInt(total)) / 1e6, launches, used,
    });
    var order: [max]usize = undefined;
    for (order[0..used], 0..) |*o, i| o.* = i;
    var shown: usize = 0;
    while (shown < used) : (shown += 1) {
        var best = shown;
        for (order[shown..used], shown..) |o, j| {
            if (ns[o] > ns[order[best]]) best = j;
        }
        std.mem.swap(usize, &order[shown], &order[best]);
        const i = order[shown];
        const t: f64 = @floatFromInt(ns[i]);
        const c: f64 = @floatFromInt(calls[i]);
        if (t / 1e6 < 0.5) break;
        std.debug.print("kernel log: {d:.3} ms {d} launches {d:.1} us each grid {d} {s}\n", .{
            t / 1e6, calls[i], t / 1e3 / c, grids[i], nameOf(handles[i]),
        });
    }
    ns = @splat(0);
    calls = @splat(0);
    grids = @splat(0);
    handles = @splat(null);
    used = 0;
    window_start = 0;
    last_end = 0;
}
