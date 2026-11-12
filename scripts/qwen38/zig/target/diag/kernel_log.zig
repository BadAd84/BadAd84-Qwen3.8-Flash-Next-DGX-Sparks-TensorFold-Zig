//! TF_CUDA_KERNEL_LOG=1 with TF_FLASHNEXT_WINDOW_GRAPH=0: every launch waited for, its wall time booked to its kernel.
const std = @import("std");
const platform = @import("sys");
const abi = @import("abi.zig");
const Driver = @import("driver.zig").Driver;
const Function = @import("module.zig").Function;
const Stream = @import("stream.zig").Stream;

const max = 512;
const shown_most = 48;
var known = false;
var enabled = false;
var driver: ?*const Driver = null;
var handles: [max]abi.Function = @splat(null);
var ns: [max]u64 = @splat(0);
var calls: [max]u64 = @splat(0);
var used: usize = 0;

/// On only with the graphs off: a launch being captured into a graph cannot be waited for.
pub fn on() bool {
    if (!known) {
        known = true;
        const log = platform.getenv("TF_CUDA_KERNEL_LOG") orelse "";
        const graphs = platform.getenv("TF_FLASHNEXT_WINDOW_GRAPH") orelse "";
        enabled = std.mem.eql(u8, log, "1") and std.mem.eql(u8, graphs, "0");
    }
    return enabled;
}

pub fn now() u64 {
    var ts: platform.c.timespec = undefined;
    if (platform.c.clock_gettime(platform.c.CLOCK.MONOTONIC, &ts) != 0) return 0;
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

/// The launch queued since `t0` is waited for and its time booked to its kernel.
pub fn booked(f: Function, stream: Stream, t0: u64) void {
    _ = f.d.api.cuStreamSynchronize(stream.handle);
    const dt = now() - t0;
    driver = f.d;
    var i: usize = 0;
    while (i < used and handles[i] != f.handle) i += 1;
    if (i == used) {
        if (used == max) return;
        handles[i] = f.handle;
        used += 1;
    }
    ns[i] += dt;
    calls[i] += 1;
}

/// The kernels by time over `rounds` rounds, the largest first; the table then starts over.
pub fn dump(rounds: f64) void {
    if (!on() or used == 0 or rounds <= 0) return;
    const d = driver orelse return;
    var order: [max]usize = undefined;
    for (order[0..used], 0..) |*o, i| o.* = i;
    var total: u64 = 0;
    var launches: u64 = 0;
    for (ns[0..used], calls[0..used]) |v, c| {
        total += v;
        launches += c;
    }
    std.debug.print("kernel log: {d:.2} ms and {d:.1} launches a round in {d} kernels over {d:.0} rounds\n", .{ @as(f64, @floatFromInt(total)) / 1e6 / rounds, @as(f64, @floatFromInt(launches)) / rounds, used, rounds });
    var shown: usize = 0;
    while (shown < @min(used, shown_most)) : (shown += 1) {
        var best = shown;
        for (order[shown..used], shown..) |o, j| {
            if (ns[o] > ns[order[best]]) best = j;
        }
        std.mem.swap(usize, &order[shown], &order[best]);
        const i = order[shown];
        const t: f64 = @floatFromInt(ns[i]);
        const c: f64 = @floatFromInt(calls[i]);
        std.debug.print("kernel log: {d:.3} ms {d:.1} launches {d:.1} us each {s}\n", .{ t / 1e6 / rounds, c / rounds, t / 1e3 / c, d.functionName(handles[i]) });
    }
    ns = @splat(0);
    calls = @splat(0);
}
