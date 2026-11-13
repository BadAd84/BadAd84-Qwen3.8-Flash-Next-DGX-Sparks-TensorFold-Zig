//! TF_FLASHNEXT_EXPERT_LOG=1: an expert launch prints the items its grid covers, the items the plan really made and
//! the matrix shape behind one item, so a round's expert bytes can be counted. It waits for the launch and reads
//! four bytes back, so the run is slower: its tok/s is not a speed result.
const std = @import("std");
const stream_ = @import("stream.zig");

var known = false;
var enabled = false;

pub fn on() bool {
    if (!known) {
        known = true;
        const v = std.c.getenv("TF_FLASHNEXT_EXPERT_LOG");
        enabled = v != null and std.mem.eql(u8, std.mem.span(v.?), "1");
    }
    return enabled;
}

/// `counts` is the plan's item count on the device; `n` and `k` are one item's matrix, `mats` how many it reads.
pub fn note(s: stream_.Stream, name: []const u8, items: usize, counts: u64, grid: u32, n: usize, k: usize, mats: usize) void {
    if (!on()) return;
    var made: i32 = -1;
    _ = s.d.api.cuStreamSynchronize(s.handle);
    _ = s.d.api.cuMemcpyDtoH_v2(@ptrCast(&made), counts, 4);
    std.debug.print("expert log: {s} grid {d} items {d} made {d} mats {d} n {d} k {d}\n", .{ name, grid, items, made, mats, n, k });
}
