//! TF_FLASHNEXT_EXPERT_LOG=1: an expert launch prints the items its grid covers, the items the plan really made, the
//! matrix behind one item, the launch's booked time and weight base; a gate/up call also prints every item's expert
//! and pair count (its down call runs the same plan), so a round's unique experts, passes and bytes can be counted.
//! It waits for the launch and reads the plan back, so the run is slower: its tok/s is not a speed result.
const std = @import("std");
const stream_ = @import("stream.zig");
const kernel_log = @import("kernel_log.zig");

var known = false;
var enabled = false;
var plan: [3 * 6144]i32 = undefined;
var line: [6144 * 12 + 256]u8 = undefined;

pub fn on() bool {
    if (!known) {
        known = true;
        const v = std.c.getenv("TF_FLASHNEXT_EXPERT_LOG");
        enabled = v != null and std.mem.eql(u8, std.mem.span(v.?), "1");
    }
    return enabled;
}

/// `counts` and `items` are the plan's item count and items on the device; `n` and `k` one item's matrix, `mats` how
/// many it reads, `w` the launch's weight base (one per layer, so it names the layer).
pub fn note(s: stream_.Stream, name: []const u8, items: usize, counts: u64, grid: u32, n: usize, k: usize, mats: usize, items_ptr: u64, w: u64) void {
    if (!on()) return;
    var made: i32 = -1;
    _ = s.d.api.cuStreamSynchronize(s.handle);
    _ = s.d.api.cuMemcpyDtoH_v2(@ptrCast(&made), counts, 4);
    const us = @as(f64, @floatFromInt(kernel_log.last_ns)) / 1e3;
    var at: usize = (std.fmt.bufPrint(&line, "expert log: {s} grid {d} items {d} made {d} mats {d} n {d} k {d} us {d:.1} w {x}", .{ name, grid, items, made, mats, n, k, us, w }) catch return).len;
    if (made > 0 and std.mem.indexOf(u8, name, "up") != null) {
        const m: usize = @min(@as(usize, @intCast(made)), plan.len / 3);
        _ = s.d.api.cuMemcpyDtoH_v2(@ptrCast(&plan), items_ptr, m * 3 * 4);
        at += (std.fmt.bufPrint(line[at..], " ids", .{}) catch return).len;
        for (0..m) |i| at += (std.fmt.bufPrint(line[at..], " {d}:{d}", .{ plan[3 * i], plan[3 * i + 2] }) catch break).len;
    }
    std.debug.print("{s}\n", .{line[0..at]});
}
