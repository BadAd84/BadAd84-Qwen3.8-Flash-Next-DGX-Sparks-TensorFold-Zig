//! The prompt cache's tests: a fake family whose state is a running sum, so a resumed pass equals a fresh one exactly when it should.
const std = @import("std");
const pc = @import("prompt_cache.zig");
const Snapshots = pc.Snapshots;
const Saved = pc.Saved;
const Store = pc.Store;
const Plan = pc.Plan;
const Allocator = std.mem.Allocator;

/// Rank 1's bytes: it applies a request's drops before that request's keeps; drops made during a pass wait for the next request.
const Peer = struct {
    held: u64 = 0,
    pending: u64 = 0,
    max: u64 = 0,
    in_pass: bool = false,

    fn request(p: *Peer) void {
        p.held -= p.pending;
        p.pending = 0;
    }
};

/// A family over host memory for tests: its live state is a position and a running sum of the prompt's tokens.
const Fake = struct {
    gpa: Allocator,
    at: u32 = 0,
    salt: u64 = 0, // the cache salt its passes keep under
    sum: u64 = 0,
    fail_save: bool = false,
    fail_restore: bool = false,
    live: usize = 0,
    spare_bytes: u64 = 0,
    peer: ?*Peer = null, // speed-up mode's rank 1: it keeps the same states and drops them only when a request names them

    const State = struct { at: u32, sum: u64 };

    fn snapshots(f: *Fake) Snapshots {
        return .{ .ptr = f, .vtable = &.{ .bytes = bytesFn, .save = saveFn, .restore = restoreFn, .drop = dropFn } };
    }
    /// A pool-like family: a kept state holds 10 bytes under `bytes`, and a dropped one's storage stays spare.
    fn pooled(f: *Fake) Snapshots {
        return .{ .ptr = f, .vtable = &.{ .bytes = bytesFn, .save = savePooledFn, .restore = restoreFn, .drop = dropSpareFn, .charged = chargedFn, .spare = spareFn, .trim = trimFn, .reuses = reusesFn } };
    }
    fn reusesFn(ptr: *anyopaque, at: u32) bool {
        return of(ptr).spare_bytes >= 90 + at;
    }
    fn savePooledFn(ptr: *anyopaque, owner: ?*anyopaque, at: u32) anyerror!Saved {
        const st = try saveFn(ptr, owner, at);
        const f = of(ptr);
        if (f.spare_bytes >= 90 + at) f.spare_bytes -= 90 + at; // the spare storage took it
        return st;
    }
    fn chargedFn(_: *anyopaque, saved: Saved) u64 {
        const st: *State = @ptrCast(@alignCast(saved));
        return 90 + st.at;
    }
    fn dropSpareFn(ptr: *anyopaque, saved: Saved) void {
        const st: *State = @ptrCast(@alignCast(saved));
        of(ptr).spare_bytes += 90 + st.at;
        dropFn(ptr, saved);
    }
    fn spareFn(ptr: *anyopaque) u64 {
        return of(ptr).spare_bytes;
    }
    fn trimFn(ptr: *anyopaque, room_: u64) void {
        const f = of(ptr);
        f.spare_bytes = @min(f.spare_bytes, room_);
    }
    fn of(ptr: *anyopaque) *Fake {
        return @ptrCast(@alignCast(ptr));
    }
    fn bytesFn(_: *anyopaque, at: u32) u64 {
        return 100 + at;
    }
    fn saveFn(ptr: *anyopaque, _: ?*anyopaque, at: u32) anyerror!Saved {
        const f = of(ptr);
        if (f.fail_save) return error.CopyFailed;
        if (at != f.at) return error.NotAtMark;
        const st = try f.gpa.create(State);
        st.* = .{ .at = f.at, .sum = f.sum };
        f.live += 1;
        if (f.peer) |p| {
            p.held += 100 + at;
            p.max = @max(p.max, p.held);
        }
        return st;
    }
    fn restoreFn(ptr: *anyopaque, _: ?*anyopaque, saved: Saved) anyerror!void {
        const f = of(ptr);
        if (f.fail_restore) return error.CopyFailed;
        const st: *State = @ptrCast(@alignCast(saved));
        f.at, f.sum = .{ st.at, st.sum };
    }
    fn dropFn(ptr: *anyopaque, saved: Saved) void {
        const f = of(ptr);
        const st: *State = @ptrCast(@alignCast(saved));
        if (f.peer) |p| { // dropped before the pass: named in this request; during it: in the next one
            if (p.in_pass) p.pending += 100 + st.at else p.held -= 100 + st.at;
        }
        f.gpa.destroy(st);
        f.live -= 1;
    }

    /// A prompt pass from `plan.from`, keeping at each mark; returns the sum a fresh pass would give.
    fn pass(f: *Fake, s: *Store, prompt: []const u32, plan: Plan) u64 {
        if (plan.from == 0) f.* = .{ .gpa = f.gpa, .fail_save = f.fail_save, .fail_restore = f.fail_restore, .live = f.live, .spare_bytes = f.spare_bytes, .peer = f.peer, .salt = f.salt };
        if (f.peer) |p| p.in_pass = true;
        defer if (f.peer) |p| {
            p.in_pass = false;
        };
        var mi: usize = 0;
        for (prompt[plan.from..]) |t| {
            f.sum = f.sum *% 31 +% t;
            f.at += 1;
            if (mi < plan.marks.len and plan.marks[mi] == f.at) {
                _ = s.keep(prompt, f.at, null, f.salt);
                mi += 1;
            }
        }
        return f.sum;
    }
};

fn fresh(prompt: []const u32) u64 {
    var sum: u64 = 0;
    for (prompt) |t| sum = sum *% 31 +% t;
    return sum;
}

test "a growing conversation resumes each turn where the last one's history ended, and equals a fresh pass" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .lookahead = 1, .min_prompt = 0 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 9, 9 }; // history 5, then a two-token generation prompt
    var p = try s.begin(a, &t1, 5, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqualSlices(u32, &.{5}, p.marks);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    const t2 = [_]u32{ 1, 2, 3, 4, 5, 9, 7, 7, 6, 6, 9, 9 }; // the reply and a tool result, history 10
    p = try s.begin(a, &t2, 10, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 5), p.from);
    try std.testing.expectEqualSlices(u32, &.{10}, p.marks);
    try std.testing.expectEqual(fresh(&t2), f.pass(&s, &t2, p));
    const edited = [_]u32{ 1, 2, 3, 8, 5, 9, 7, 7, 6, 6, 9, 9 }; // an earlier turn edited: nothing resumes past it
    p = try s.begin(a, &edited, 10, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqual(fresh(&edited), f.pass(&s, &edited, p));
    try std.testing.expectEqual(@as(u64, 1), s.counts.hits);
    try std.testing.expectEqual(@as(u64, 2), s.counts.misses);
}

test "an entry keys its lookahead tokens: a prompt that differs right after the state does not resume it" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .lookahead = 1, .min_prompt = 0 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 9 };
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0)); // keeps [1 2 3 4] + 5
    try std.testing.expect(s.find(&.{ 1, 2, 3, 4, 6, 9 }, &.{}, 0) == null);
    try std.testing.expectEqual(@as(u32, 4), s.find(&.{ 1, 2, 3, 4, 5, 6 }, &.{}, 0).?.at);
    try std.testing.expect(s.find(&.{ 1, 2, 3, 4 }, &.{}, 0) == null); // the lookahead token must be in the prompt
}

test "planned families resume and keep only at the request's chunk starts" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .planned = true, .min_prompt = 0 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const p = try s.begin(a, &t1, 7, &.{}, &.{ 4, 6 }, null, 0);
    try std.testing.expectEqualSlices(u32, &.{6}, p.marks); // history 7 floored to the start at 6
    _ = f.pass(&s, &t1, p);
    try std.testing.expect(s.find(&.{ 1, 2, 3, 4, 5, 6, 7, 9 }, &.{4}, 0) == null); // 6 is not one of this prompt's starts
    try std.testing.expectEqual(@as(u32, 6), s.find(&.{ 1, 2, 3, 4, 5, 6, 7, 9 }, &.{ 4, 6 }, 0).?.at);
}

test "eviction frees a conversation's superseded state first, then the oldest; a state past the budget is refused" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0 }, 330); // fake bytes: 100 + at
    defer s.deinit();
    const other = [_]u32{ 5, 5, 5, 5 };
    _ = f.pass(&s, &other, try s.begin(a, &other, 3, &.{}, &.{}, null, 0)); // 103 bytes
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0)); // 104: 207 held
    const t2 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    _ = f.pass(&s, &t2, try s.begin(a, &t2, 6, &.{}, &.{}, null, 0)); // 106 more: 313
    try std.testing.expectEqual(@as(usize, 3), s.entries.items.len);
    const t3 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 };
    _ = f.pass(&s, &t3, try s.begin(a, &t3, 8, &.{}, &.{}, null, 0)); // 108: t1's state (extended by later turns) goes first
    try std.testing.expectEqual(@as(usize, 3), s.entries.items.len);
    try std.testing.expect(s.find(&.{ 5, 5, 5, 5 }, &.{}, 0) != null);
    try std.testing.expectEqual(@as(u32, 8), s.find(&t3, &.{}, 0).?.at);
    const big: [300]u32 = @splat(7);
    _ = f.pass(&s, &big, try s.begin(a, &big, 299, &.{}, &.{}, null, 0)); // 399 > 330: refused, nothing evicted
    try std.testing.expectEqual(@as(u64, 1), s.counts.refused);
    try std.testing.expectEqual(@as(usize, 3), s.entries.items.len);
    try std.testing.expect(s.held <= s.budget);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "a failed copy keeps nothing and a failed restore prefills from the start" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa, .fail_save = true };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(usize, 0), s.entries.items.len);
    try std.testing.expectEqual(@as(u64, 1), s.counts.failed);
    f.fail_save = false;
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(usize, 1), s.entries.items.len);
    f.fail_restore = true;
    const t2 = [_]u32{ 1, 2, 3, 4, 5, 6, 7 };
    const p = try s.begin(a, &t2, 6, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqual(@as(usize, 0), s.entries.items.len); // the entry that failed is gone
    try std.testing.expectEqual(fresh(&t2), f.pass(&s, &t2, p));
}

test "marks: the stable prefix with the last prompt and shared blocks, past the resume point, before the end" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .lookahead = 1, .min_gap = 2, .min_prompt = 0 }, 1 << 20);
    defer s.deinit();
    const prompt = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12 };
    const prev = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 0, 0 };
    try std.testing.expectEqualSlices(u32, &.{ 3, 7, 10 }, try s.marks(a, &prompt, 0, 10, &.{ 3, 12, 0 }, &.{}, &prev));
    try std.testing.expectEqualSlices(u32, &.{10}, try s.marks(a, &prompt, 7, 10, &.{3}, &.{}, &prev));
    try std.testing.expectEqualSlices(u32, &.{}, try s.marks(a, &prompt, 0, 0, &.{}, &.{}, &.{})); // a raw prompt keeps nothing
    try std.testing.expectEqualSlices(u32, &.{10}, try s.marks(a, &prompt, 0, 10, &.{9}, &.{}, &.{})); // a block next to the history
}

test "prompts under min_prompt keep nothing (their extra prompt call would cost more than reuse saves), longer ones keep as before" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .lookahead = 1, .min_prompt = 8 }, 1 << 20);
    defer s.deinit();
    const short = [_]u32{ 1, 2, 3, 4, 5, 9, 9 }; // 7 tokens, history 5
    const p = try s.begin(a, &short, 5, &.{}, &.{}, null, 0);
    try std.testing.expectEqualSlices(u32, &.{}, p.marks);
    try std.testing.expectEqual(fresh(&short), f.pass(&s, &short, p));
    try std.testing.expectEqual(@as(usize, 0), s.entries.items.len);
    const long = [_]u32{ 1, 2, 3, 4, 5, 9, 7, 7, 9, 9 }; // 10 tokens: the next turn keeps its history, resuming nothing
    const q = try s.begin(a, &long, 8, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), q.from);
    try std.testing.expectEqualSlices(u32, &.{8}, q.marks);
    try std.testing.expectEqual(fresh(&long), f.pass(&s, &long, q));
    try std.testing.expectEqual(@as(u32, 8), s.find(&.{ 1, 2, 3, 4, 5, 9, 7, 7, 9, 9, 4 }, &.{}, 0).?.at);
}

test "kept states charge their real storage, a save takes spare storage first, and spare stays inside the budget" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.pooled(), .{ .min_prompt = 0 }, 330); // new storage 100 + at, a kept state 90 + at
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(u64, 94), s.held);
    f.spare_bytes = 120; // a buffer readied while idle
    try std.testing.expectEqual(@as(u64, 116), s.room());
    const other = [_]u32{ 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5 };
    _ = f.pass(&s, &other, try s.begin(a, &other, 10, &.{}, &.{}, null, 0)); // takes the readied buffer: nothing evicted
    try std.testing.expectEqual(@as(u64, 194), s.held);
    try std.testing.expectEqual(@as(u64, 20), s.spare());
    try std.testing.expectEqual(@as(u64, 0), s.counts.evicted);
    var t2: [102]u32 = undefined;
    for (&t2, 1..) |*t, i| t.* = @intCast(i);
    _ = f.pass(&s, &t2, try s.begin(a, &t2, 101, &.{}, &.{}, null, 0)); // resumes t1's; 201 new: the spare shrinks, then `other` goes
    try std.testing.expectEqual(@as(u64, 1), s.counts.evicted);
    try std.testing.expectEqual(@as(u64, 94 + 191), s.held);
    try std.testing.expect(s.held + s.spare() <= s.budget);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "a shared system cut outlives its own conversation's turns: a second conversation resumes it after cold prompts fill the budget" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0, .min_gap = 1 }, 600); // bytes 100 + at
    defer s.deinit();
    var c1: [30]u32 = @splat(9);
    var c2: [30]u32 = @splat(8);
    for ([_][]u32{ &c1, &c2 }) |c| { // cold prompts first
        _ = f.pass(&s, c, try s.begin(a, c, 29, &.{}, &.{}, null, 0));
        try std.testing.expect(s.held <= s.budget);
    }
    var conv: [45]u32 = undefined;
    for (&conv, 1..) |*t, i| t.* = @intCast(i); // a 20-token system block, then the turns
    for ([_]u32{ 25, 35, 45 }, [_]u32{ 24, 34, 44 }) |len, history| {
        _ = f.pass(&s, conv[0..len], try s.begin(a, conv[0..len], history, &.{20}, &.{}, null, 0));
        try std.testing.expect(s.held <= s.budget);
    }
    var c3: [60]u32 = @splat(7);
    _ = f.pass(&s, &c3, try s.begin(a, &c3, 59, &.{}, &.{}, null, 0));
    try std.testing.expect(s.held <= s.budget);
    var other: [25]u32 = undefined;
    @memcpy(other[0..20], conv[0..20]);
    for (other[20..], 0..) |*t, i| t.* = @intCast(90 + i);
    const plan = try s.begin(a, &other, 24, &.{20}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 20), plan.from); // the cut survived the first conversation's turns
    try std.testing.expectEqual(fresh(&other), f.pass(&s, &other, plan));
    try std.testing.expect(s.held <= s.budget);
}

test "a pass makes room for every state it keeps before it starts, so a peer told of the evictions with the request stays inside the budget" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var peer: Peer = .{};
    var f: Fake = .{ .gpa = gpa, .peer = &peer };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0, .min_gap = 1 }, 600); // bytes 100 + at
    defer s.deinit();
    var conv: [200]u32 = undefined;
    for (&conv, 1..) |*t, i| t.* = @intCast(i);
    var len: u32 = 30;
    while (len <= 200) : (len += 17) { // a conversation's turns: each keeps its history and the stable prefix, two states a pass
        peer.request(); // the drops the last pass made reach the peer with this request
        const plan = try s.begin(a, conv[0..len], len - 3, &.{20}, &.{}, null, 0); // its own evictions too, before the peer keeps anything
        _ = f.pass(&s, conv[0..len], plan);
        try std.testing.expect(s.held <= s.budget);
    }
    try std.testing.expect(s.counts.evicted > 0);
    try std.testing.expect(peer.max <= s.budget); // evicting at keep time instead, the peer holds the old states until the next request
}

test "a state a peer cannot resume is forgotten: the next prompt misses instead of asking again" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0 }, 1000);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    _ = f.pass(&s, &t1, try s.begin(a, &t1, 4, &.{}, &.{}, null, 0));
    const t2 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const plan = try s.begin(a, &t2, 6, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 4), plan.from);
    s.forget(&t2, plan.from, 0); // the peer's answer: it lacks that state
    try std.testing.expectEqual(@as(u64, 1), s.counts.failed);
    try std.testing.expectEqual(@as(?*pc.Entry, null), s.find(&t2, &.{}, 0));
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "a whole-prompt state: the very prompt resumes it with nothing left to prefill, a longer one from it, a shorter one keeps nothing" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 100, .whole = true, .whole_min = 4 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 }; // a completion: no history
    var p = try s.begin(a, &t1, 0, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqualSlices(u32, &.{6}, p.marks);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    try std.testing.expect(s.entries.items[0].whole and s.entries.items[0].short);
    p = try s.begin(a, &t1, 0, &.{}, &.{}, null, 0); // the replay
    try std.testing.expectEqual(@as(u32, 6), p.from);
    try std.testing.expectEqualSlices(u32, &.{}, p.marks);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    const t2 = [_]u32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    p = try s.begin(a, &t2, 0, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 6), p.from);
    try std.testing.expectEqualSlices(u32, &.{8}, p.marks);
    try std.testing.expectEqual(fresh(&t2), f.pass(&s, &t2, p));
    const tiny = [_]u32{ 1, 2, 3 }; // under whole_min
    try std.testing.expectEqualSlices(u32, &.{}, try s.marks(a, &tiny, 0, 0, &.{}, &.{}, &.{}));
    var off = Store.init(gpa, f.snapshots(), .{ .min_prompt = 100 }, 1 << 20); // a family without whole states
    defer off.deinit();
    try std.testing.expectEqualSlices(u32, &.{}, try off.marks(a, &t1, 0, 0, &.{}, &.{}, &.{}));
}

test "a state kept inside a longer prompt never replays a prompt that ends there; that prompt's own whole state replaces it" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0, .min_gap = 2, .whole = true, .whole_min = 4 }, 1 << 20);
    defer s.deinit();
    const chat = [_]u32{ 1, 2, 3, 4, 5, 9, 9, 9, 9, 9 }; // history 5, then the generation prompt
    var p = try s.begin(a, &chat, 5, &.{}, &.{}, null, 0);
    try std.testing.expectEqualSlices(u32, &.{ 5, 10 }, p.marks);
    _ = f.pass(&s, &chat, p);
    const head = [_]u32{ 1, 2, 3, 4, 5 };
    try std.testing.expect(s.find(&head, &.{}, 0) == null); // the state at 5 has no last row to draw from
    p = try s.begin(a, &head, 0, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqualSlices(u32, &.{5}, p.marks);
    try std.testing.expectEqual(fresh(&head), f.pass(&s, &head, p));
    try std.testing.expectEqual(@as(usize, 2), s.entries.items.len);
    try std.testing.expectEqual(@as(u32, 5), s.find(&head, &.{}, 0).?.at);
    try std.testing.expectEqual(s.entries.items.len, f.live);
    const near = [_]u32{ 1, 2, 3, 4, 5, 9 }; // a history mark within min_gap of the end: that mark only
    try std.testing.expectEqualSlices(u32, &.{5}, try s.marks(a, &near, 0, 5, &.{}, &.{}, &.{}));
}

test "cache_salt: a salted prompt resumes only states its own salt kept; unsalted prompts share theirs as before" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(u64, 0), pc.saltKey(null));
    const ka = pc.saltKey("cold-replay-1");
    const kb = pc.saltKey("cold-replay-2");
    try std.testing.expect(ka != 0 and kb != 0 and ka != kb);
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0, .whole = true, .whole_min = 1 }, 1 << 20);
    defer s.deinit();
    const t1 = [_]u32{ 1, 2, 3, 4, 5, 6 };
    f.salt = ka;
    var p = try s.begin(a, &t1, 0, &.{}, &.{}, null, ka); // cold under salt A
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    try std.testing.expect(s.find(&t1, &.{}, 0) == null); // unsalted: cold
    try std.testing.expect(s.find(&t1, &.{}, kb) == null); // another salt: cold
    p = try s.begin(a, &t1, 0, &.{}, &.{}, null, ka); // the replay under A: warm
    try std.testing.expectEqual(@as(u32, 6), p.from);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    f.salt = 0;
    p = try s.begin(a, &t1, 0, &.{}, &.{}, null, 0); // unsalted: its own state, beside A's
    try std.testing.expectEqual(@as(u32, 0), p.from);
    try std.testing.expectEqual(fresh(&t1), f.pass(&s, &t1, p));
    try std.testing.expectEqual(@as(usize, 2), s.entries.items.len);
    try std.testing.expectEqual(@as(u64, 0), s.find(&t1, &.{}, 0).?.salt);
    try std.testing.expectEqual(ka, s.find(&t1, &.{}, ka).?.salt);
    try std.testing.expect(s.find(&t1, &.{}, kb) == null);
    s.forget(&t1, 6, kb); // another salt's forget leaves both
    try std.testing.expectEqual(@as(usize, 2), s.entries.items.len);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "short prompts' whole states go before a long prompt's: a stream of short replays never pushes a long one out" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 10, .min_gap = 1, .whole = true, .whole_min = 1 }, 400); // bytes 100 + at
    defer s.deinit();
    var long: [20]u32 = undefined;
    for (&long, 1..) |*t, i| t.* = @intCast(i);
    _ = f.pass(&s, &long, try s.begin(a, &long, 0, &.{}, &.{}, null, 0)); // 120 bytes, the oldest
    for (0..6) |k| {
        const short = [_]u32{ 50, 51, 52, 53, @intCast(k) };
        _ = f.pass(&s, &short, try s.begin(a, &short, 0, &.{}, &.{}, null, 0)); // 105 each
        try std.testing.expect(s.held <= s.budget);
    }
    try std.testing.expect(s.counts.evicted >= 4);
    try std.testing.expectEqual(@as(u32, 20), s.find(&long, &.{}, 0).?.at);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "a long prompt frees short prompts' whole states before an older long prompt's" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 10, .min_gap = 1, .whole = true, .whole_min = 1 }, 260); // bytes 100 + at
    defer s.deinit();
    var first: [20]u32 = undefined; // a long prompt's whole state, 120 bytes, the oldest
    for (&first, 1..) |*t, i| t.* = @intCast(i);
    _ = f.pass(&s, &first, try s.begin(a, &first, 0, &.{}, &.{}, null, 0));
    const short = [_]u32{ 50, 51, 52, 53, 54 }; // a short prompt's whole state, 105: 225 held
    _ = f.pass(&s, &short, try s.begin(a, &short, 0, &.{}, &.{}, null, 0));
    var second: [20]u32 = @splat(7); // another long prompt (extends nothing): 120 more needs one state's room
    second[19] = 8;
    _ = f.pass(&s, &second, try s.begin(a, &second, 0, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(u64, 1), s.counts.evicted);
    try std.testing.expect(s.find(&short, &.{}, 0) == null); // the short prompt's state went
    try std.testing.expectEqual(@as(u32, 20), s.find(&first, &.{}, 0).?.at); // not the older long one
    try std.testing.expectEqual(@as(u32, 20), s.find(&second, &.{}, 0).?.at);
    try std.testing.expect(s.held <= s.budget);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "TENSORFOLD_PROMPT_CACHE_WHOLE is 0 or 1 and WHOLE_MIN a token count from 1; anything else refused, never read as on or off" {
    const base: pc.Rules = .{};
    const off = try pc.wholeRules(base, true, null, null);
    try std.testing.expect(!off.whole);
    try std.testing.expectEqual(base.whole_min, off.whole_min);
    try std.testing.expect(!(try pc.wholeRules(base, true, "0", null)).whole);
    const on = try pc.wholeRules(base, true, "1", "300");
    try std.testing.expect(on.whole);
    try std.testing.expectEqual(@as(u32, 300), on.whole_min);
    try std.testing.expectEqual(base.min_prompt, on.min_prompt); // the other rules untouched
    try std.testing.expectError(error.BadSetting, pc.wholeRules(base, false, "1", null)); // the engine cannot
    for ([_][]const u8{ "", "2", "on", "true", "1 ", "-1" }) |v| try std.testing.expectError(error.BadSetting, pc.wholeRules(base, true, v, null));
    for ([_][]const u8{ "", "0", "-5", "x", "4294967296", "1e3" }) |v| try std.testing.expectError(error.BadSetting, pc.wholeRules(base, true, "1", v));
}

test "a short prompt's state never displaces a longer prompt's: the turn a conversation's turns resume outlives a stream of short cold prompts" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    // an agent's next turn on a kept ~100k conversation beside cold short prompts (the measured lost state, scaled
    // down): bytes 100 + at, a 2-token generation prompt
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 20, .min_gap = 3, .whole = true, .whole_min = 4 }, 600);
    defer s.deinit();
    var prime: [32]u32 = undefined; // the conversation's first turn: history 30, then the generation prompt
    for (prime[0..30], 1..) |*t, i| t.* = @intCast(i);
    prime[30..32].* = .{ 90, 91 };
    var p = try s.begin(a, &prime, 30, &.{}, &.{}, null, 0);
    try std.testing.expectEqualSlices(u32, &.{30}, p.marks); // its history (the whole prompt is within min_gap)
    _ = f.pass(&s, &prime, p);
    p = try s.begin(a, &prime, 30, &.{}, &.{}, null, 0); // the turn re-sent: its whole state
    try std.testing.expectEqual(@as(u32, 30), p.from);
    try std.testing.expectEqualSlices(u32, &.{32}, p.marks);
    _ = f.pass(&s, &prime, p);
    var turn: [41]u32 = undefined; // the reply, a new user message, the generation prompt
    @memcpy(turn[0..32], &prime);
    turn[32..41].* = .{ 7, 7, 60, 61, 62, 63, 64, 90, 91 };
    p = try s.begin(a, &turn, 39, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 32), p.from);
    try std.testing.expectEqual(fresh(&turn), f.pass(&s, &turn, p)); // 130 + 132 + 139 held: the 32-token state is superseded by the turn's
    for (0..8) |k| { // cold short prompts (whole states, 110 bytes): each frees only an older one
        const cold = [_]u32{ 50, 51, 52, 53, 54, 55, 56, 57, @intCast(k), 99 };
        p = try s.begin(a, &cold, 8, &.{}, &.{}, null, 0);
        try std.testing.expectEqualSlices(u32, &.{10}, p.marks);
        try std.testing.expectEqual(fresh(&cold), f.pass(&s, &cold, p));
        try std.testing.expect(s.held <= s.budget);
    }
    try std.testing.expectEqual(@as(u64, 0), s.counts.refused);
    try std.testing.expect(s.counts.evicted >= 6);
    turn[34] = 70; // another new user message on the same conversation
    p = try s.begin(a, &turn, 39, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 32), p.from); // the conversation's state is still kept
    try std.testing.expectEqual(fresh(&turn), f.pass(&s, &turn, p));
    try std.testing.expectEqual(s.entries.items.len, f.live);
}

test "a short prompt whose state would need a longer prompt's room keeps nothing and frees nothing in vain" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 20, .min_gap = 3, .whole = true, .whole_min = 4 }, 245); // bytes 100 + at
    defer s.deinit();
    var long: [30]u32 = undefined; // a completion: its whole state only, 130 bytes
    for (&long, 1..) |*t, i| t.* = @intCast(i);
    _ = f.pass(&s, &long, try s.begin(a, &long, 0, &.{}, &.{}, null, 0));
    const small = [_]u32{ 50, 51, 52, 53, 54, 55, 56, 57, 58, 59 }; // 110 bytes: 240 held
    _ = f.pass(&s, &small, try s.begin(a, &small, 0, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(u64, 240), s.held);
    var big: [18]u32 = @splat(3); // a short prompt of 118 bytes: even with the short state gone 130 + 118 passes 245
    big[17] = 4;
    const p = try s.begin(a, &big, 0, &.{}, &.{}, null, 0);
    try std.testing.expectEqualSlices(u32, &.{}, p.marks); // refused before the pass copies anything
    try std.testing.expectEqual(fresh(&big), f.pass(&s, &big, p));
    try std.testing.expectEqual(@as(u64, 1), s.counts.refused);
    try std.testing.expectEqual(@as(u64, 0), s.counts.evicted);
    try std.testing.expectEqual(@as(u32, 30), s.find(&long, &.{}, 0).?.at); // its whole state replays it
    try std.testing.expectEqual(@as(u32, 10), s.find(&small, &.{}, 0).?.at); // the short state stays too
    try std.testing.expect(!s.keep(&big, 18, null, 0)); // a keep without the plan (a peer's pass): refused the same way
    try std.testing.expectEqual(@as(u64, 2), s.counts.refused);
    try std.testing.expectEqual(@as(usize, 2), s.entries.items.len);
    try std.testing.expectEqual(s.entries.items.len, f.live);
    var g: Fake = .{ .gpa = gpa };
    var t = Store.init(gpa, g.snapshots(), .{ .min_prompt = 20, .min_gap = 3, .whole = true, .whole_min = 4 }, 352);
    defer t.deinit();
    _ = g.pass(&t, &long, try t.begin(a, &long, 0, &.{}, &.{}, null, 0)); // 130
    _ = g.pass(&t, &small, try t.begin(a, &small, 0, &.{}, &.{}, null, 0)); // 110
    const other = [_]u32{ 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71 }; // 112: 352 held
    _ = g.pass(&t, &other, try t.begin(a, &other, 0, &.{}, &.{}, null, 0));
    const more = small ++ [_]u32{ 1, 2, 3, 4 }; // extends `small` (resumed, so it cannot go): 114 more needs `long`'s room
    const q = try t.begin(a, &more, 0, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 10), q.from);
    try std.testing.expectEqualSlices(u32, &.{}, q.marks);
    try std.testing.expectEqual(fresh(&more), g.pass(&t, &more, q));
    try std.testing.expectEqual(@as(u64, 0), t.counts.evicted);
    try std.testing.expectEqual(@as(u32, 12), t.find(&other, &.{}, 0).?.at);
    try std.testing.expectEqual(t.entries.items.len, g.live);
}

test "a turn resumed again after a continuation kept a longer state is a branch point: its continuations never supersede it" {
    const gpa = std.testing.allocator;
    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const a = arena.allocator();
    var f: Fake = .{ .gpa = gpa };
    var s = Store.init(gpa, f.snapshots(), .{ .min_prompt = 0, .min_gap = 3 }, 420); // bytes 100 + at
    defer s.deinit();
    var base: [20]u32 = undefined; // a turn: history 18
    for (&base, 1..) |*t, i| t.* = @intCast(i);
    _ = f.pass(&s, &base, try s.begin(a, &base, 18, &.{}, &.{}, null, 0)); // 118
    var branch: [28]u32 = undefined;
    @memcpy(branch[0..18], base[0..18]);
    for (0..2) |k| { // two continuations of it (a re-sent turn, a fork): 126 each
        for (branch[18..], 0..) |*t, i| t.* = @intCast(40 + i + 10 * k);
        const p = try s.begin(a, &branch, 26, &.{}, &.{}, null, 0);
        try std.testing.expectEqual(@as(u32, 18), p.from);
        try std.testing.expectEqual(fresh(&branch), f.pass(&s, &branch, p));
    }
    var other: [30]u32 = @splat(5); // an unrelated prompt: 128 more, one state goes
    other[29] = 6;
    _ = f.pass(&s, &other, try s.begin(a, &other, 28, &.{}, &.{}, null, 0));
    try std.testing.expectEqual(@as(u64, 1), s.counts.evicted);
    for (branch[18..], 0..) |*t, i| t.* = @intCast(80 + i); // a third continuation still resumes the branch point
    const p = try s.begin(a, &branch, 26, &.{}, &.{}, null, 0);
    try std.testing.expectEqual(@as(u32, 18), p.from);
    try std.testing.expectEqual(fresh(&branch), f.pass(&s, &branch, p));
    try std.testing.expect(s.held <= s.budget);
    try std.testing.expectEqual(s.entries.items.len, f.live);
}
