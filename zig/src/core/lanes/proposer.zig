//! Copy proposals from a stream's own context (Python SuffixLookupProposer) behind a small proposer interface.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// What the round loop asks of a proposer: a copied continuation, its evidence, and how it fared.
pub const Proposer = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        propose: *const fn (ptr: *anyopaque, context: []const u32, max_draft: i64) anyerror![]const u32,
        last_match: *const fn (ptr: *anyopaque) i64,
        observe: ?*const fn (ptr: *anyopaque, proposed: i64, accepted: i64) void = null,
        /// the context index the last `propose` copied from (null: it returned nothing, or the proposer does not say)
        last_from: ?*const fn (ptr: *anyopaque) ?usize = null,
    };

    /// Tokens valid until the next `propose`.
    pub fn propose(p: Proposer, context: []const u32, max_draft: i64) ![]const u32 {
        return p.vtable.propose(p.ptr, context, max_draft);
    }

    pub fn lastMatch(p: Proposer) i64 {
        return p.vtable.last_match(p.ptr);
    }

    pub fn observe(p: Proposer, proposed: i64, accepted: i64) void {
        if (p.vtable.observe) |f| f(p.ptr, proposed, accepted);
    }

    pub fn lastFrom(p: Proposer) ?usize {
        return if (p.vtable.last_from) |f| f(p.ptr) else null;
    }
};

pub const max_ngram = 8;
const Key = [max_ngram]u32;

pub const Params = struct {
    ngram: usize = 3,
    min_match: i64 = 6,
    max_extension: i64 = 64,
    silence_rounds: i64 = 16,
    window: usize = 4,
    confident_match: i64 = 24,
    /// after a copy window missed, find where the source resumes from the tokens the target wrote since the
    /// miss and propose from there, without waiting `min_match` matching tokens: at the miss itself the target's
    /// token tells a deletion (the source's next token) from a substitution (propose past the replaced token: a
    /// guess); later the last two tokens written are matched within `resync_span` source tokens past the miss, or
    /// the last one within `resync_near` (an insertion, a longer replacement ending). A resync that lands nothing
    /// costs a try (`resync_tries` a miss) and never counts toward the silence.
    resync: bool = false,
    resync_tries: u32 = 2,
    resync_span: usize = 24,
    resync_near: usize = 4,
    /// tokens the target may write past a miss before the resync is dropped
    resync_wait: usize = 32,
    /// rows the missed copy must have landed for a resync to be armed: a copy that was really copying (an edit
    /// mid-window) and not a coincidental match the target left at once (code and prose, where a resync would
    /// only cost rounds)
    resync_min_kept: i64 = 2,
    /// only copies whose source lies before this context index arm a resync (the host passes the prompt's
    /// length: an edit copies the prompt's text; a reply repeating its own earlier lines - code's tests, lists -
    /// leaves the source at every miss, so a resync there only costs rounds)
    resync_source_end: usize = std.math.maxInt(usize),
};

/// Continuations backed by enough matching context; silent for a while after a run of rejected proposals.
pub const SuffixLookup = struct {
    gpa: Allocator,
    params: Params,
    index: std.AutoHashMapUnmanaged(Key, std.ArrayList(u32)) = .empty,
    indexed: usize = 0,
    last_key: Key = undefined,
    recent: std.ArrayList(i64) = .empty,
    silent_for: i64 = 0,
    out: std.ArrayList(u32) = .empty,
    proposals: i64 = 0,
    proposed_tokens: i64 = 0,
    judged_tokens: i64 = 0,
    accepted_tokens: i64 = 0,
    silenced_rounds: i64 = 0,
    last_match: i64 = 0,
    last_confident: bool = false,
    /// the last proposal: where its first token sits in the context, and the context's length then
    last_from: usize = 0,
    last_len: usize = 0,
    /// the latest `propose` returned tokens: `lastFrom` answers for that proposal only (null after an empty one)
    last_out: bool = false,
    last_resync: bool = false,
    /// a miss waiting for a resync: the context index of the first draft the target rejected, the context length
    /// right after that round (the first token the target wrote instead sits at `base - 1`), and the resyncs that
    /// landed nothing since
    resync_miss: ?usize = null,
    resync_base: usize = 0,
    resync_tried: u32 = 0,
    resyncs: i64 = 0,

    pub fn init(gpa: Allocator, params: Params) !SuffixLookup {
        if (params.ngram < 1 or params.ngram > max_ngram) return error.BadNgram;
        if (params.min_match < @as(i64, @intCast(params.ngram))) return error.MinMatchBelowNgram;
        var p = params;
        p.window = @max(1, p.window);
        return .{ .gpa = gpa, .params = p };
    }

    pub fn deinit(s: *SuffixLookup) void {
        s.clearIndex();
        s.index.deinit(s.gpa);
        s.recent.deinit(s.gpa);
        s.out.deinit(s.gpa);
    }

    pub fn proposer(s: *SuffixLookup) Proposer {
        return .{ .ptr = s, .vtable = &vtable };
    }

    pub const vtable: Proposer.VTable = .{ .propose = proposeFn, .last_match = lastMatchFn, .observe = observeFn, .last_from = lastFromFn };

    fn lastFromFn(ptr: *anyopaque) ?usize {
        const s: *SuffixLookup = @ptrCast(@alignCast(ptr));
        return if (s.last_out) s.last_from else null;
    }

    fn proposeFn(ptr: *anyopaque, context: []const u32, max_draft: i64) anyerror![]const u32 {
        const s: *SuffixLookup = @ptrCast(@alignCast(ptr));
        return s.propose(context, max_draft);
    }

    fn lastMatchFn(ptr: *anyopaque) i64 {
        const s: *SuffixLookup = @ptrCast(@alignCast(ptr));
        return s.last_match;
    }

    fn observeFn(ptr: *anyopaque, proposed: i64, accepted: i64) void {
        const s: *SuffixLookup = @ptrCast(@alignCast(ptr));
        s.observe(proposed, accepted) catch {};
    }

    fn clearIndex(s: *SuffixLookup) void {
        var it = s.index.valueIterator();
        while (it.next()) |list| list.deinit(s.gpa);
        s.index.clearRetainingCapacity();
    }

    fn keyAt(s: *const SuffixLookup, context: []const u32, end: usize) Key {
        var key: Key = @splat(0xFFFF_FFFF);
        const n = s.params.ngram;
        @memcpy(key[0..n], context[end - n .. end]);
        return key;
    }

    fn extend(s: *SuffixLookup, context: []const u32) !void {
        const n = s.params.ngram;
        var position = @max(s.indexed, n - 1);
        while (position < context.len) : (position += 1) {
            const got = try s.index.getOrPut(s.gpa, s.keyAt(context, position + 1));
            if (!got.found_existing) got.value_ptr.* = .empty;
            try got.value_ptr.append(s.gpa, @intCast(position));
        }
        s.indexed = context.len;
    }

    fn matchLength(s: *const SuffixLookup, context: []const u32, end: usize) i64 {
        const len: i64 = @intCast(context.len);
        const e: i64 = @intCast(end);
        var length: i64 = 0;
        const limit = @min(s.params.max_extension, e);
        while (length < limit and context[@intCast(e - 1 - length)] == context[@intCast(len - 1 - length)]) {
            length += 1;
            if (len - 1 - length < 0) break;
        }
        return length;
    }

    /// Python `propose`: the copied continuation (owned by the proposer until the next call), or empty.
    pub fn propose(s: *SuffixLookup, context: []const u32, max_draft: i64) ![]const u32 {
        const n = s.params.ngram;
        s.out.clearRetainingCapacity();
        s.last_out = false;
        if (max_draft <= 0 or context.len < n + 1) return s.out.items;
        if (s.silent_for > 0) {
            s.silent_for -= 1;
            s.silenced_rounds += 1;
            return s.out.items;
        }
        // the context changed underneath the index (a new request): rebuild it
        const changed = s.indexed > context.len or (s.indexed != 0 and !std.mem.eql(u32, &s.keyAt(context, s.indexed), &s.last_key));
        if (changed) {
            s.clearIndex();
            s.indexed = 0;
            s.resync_miss = null;
        }
        try s.extend(context);
        s.last_key = s.keyAt(context, s.indexed);
        var best_end: i64 = -1;
        var best_len: i64 = 0;
        if (s.index.get(s.keyAt(context, context.len))) |list| {
            const positions = list.items;
            var i = positions.len;
            while (i > 0) {
                i -= 1;
                const end = positions[i] + 1;
                if (end >= context.len) continue;
                const length = s.matchLength(context, end);
                if (length > best_len) {
                    best_len = length;
                    best_end = end;
                    if (length >= s.params.max_extension) break;
                }
            }
        }
        s.last_confident = false;
        s.last_resync = false;
        s.last_match = best_len;
        var from: usize = undefined;
        if (best_end >= 0 and best_len >= s.params.min_match) {
            s.last_confident = best_len >= s.params.confident_match;
            from = @intCast(best_end);
        } else if (s.resyncFrom(context)) |at| {
            // no suffix match right after an edit: the source's continuation past it, as if it matched
            s.last_resync = true;
            s.last_match = s.params.confident_match;
            from = at;
        } else return s.out.items;
        const to = @min(context.len, from + @as(usize, @intCast(max_draft)));
        try s.out.appendSlice(s.gpa, context[from..to]);
        if (s.out.items.len > 0) {
            s.proposals += 1;
            s.last_out = true;
            s.proposed_tokens += @intCast(s.out.items.len);
            s.resyncs += @intFromBool(s.last_resync);
            s.last_from = from;
            s.last_len = context.len;
        }
        return s.out.items;
    }

    /// Where the source resumes after the pending miss (null: none pending, too old, tries spent, or the target is
    /// still inside its edit): right at the miss, the token written tells a deletion (it is the source's next
    /// token: resume past it) from a substitution (resume past the replaced token); later the last two tokens
    /// written are matched in the source within `resync_span` past the miss, or the last one within `resync_near`.
    fn resyncFrom(s: *const SuffixLookup, context: []const u32) ?usize {
        if (!s.params.resync) return null;
        const miss = s.resync_miss orelse return null;
        if (context.len < s.resync_base or context.len - s.resync_base >= s.params.resync_wait) return null;
        if (s.resync_tried >= s.params.resync_tries) return null;
        const written = context[s.resync_base - 1 ..];
        const last = written[written.len - 1];
        if (written.len >= 2) {
            const prev = written[written.len - 2];
            var j = miss;
            while (j + 1 < context.len - written.len and j <= miss + s.params.resync_span) : (j += 1) {
                if (j >= 1 and context[j - 1] == prev and context[j] == last) return j + 1;
            }
        }
        var j = miss;
        while (j + 1 < context.len - written.len and j <= miss + s.params.resync_near) : (j += 1) {
            if (context[j] == last) return j + 1;
        }
        return if (written.len == 1) miss + 1 else null; // replaced: the guess, once
    }

    pub fn observe(s: *SuffixLookup, proposed: i64, accepted: i64) !void {
        s.judged_tokens += proposed;
        s.accepted_tokens += accepted;
        if (proposed <= 0) return;
        // a miss of a copy that was landing leaves a resync pending (the source past the rejected draft); a window
        // kept whole, or one the target left at once, ends it; a resync that landed nothing spends a try and stays
        // outside the silence rule (its guesses are cheap and bounded)
        if (accepted < proposed) {
            if (s.last_resync and accepted == 0) {
                s.resync_tried += 1;
                return;
            }
            s.resync_miss = null;
            if (accepted >= s.params.resync_min_kept and s.last_from < s.params.resync_source_end) {
                s.resync_miss = s.last_from + @as(usize, @intCast(accepted));
                s.resync_base = s.last_len + @as(usize, @intCast(accepted)) + 1;
                s.resync_tried = 0;
            }
        } else s.resync_miss = null;
        try s.recent.append(s.gpa, accepted);
        if (s.recent.items.len > s.params.window) {
            const drop = s.recent.items.len - s.params.window;
            std.mem.copyForwards(i64, s.recent.items, s.recent.items[drop..]);
            s.recent.shrinkRetainingCapacity(s.params.window);
        }
        if (s.recent.items.len >= s.params.window and std.mem.max(i64, s.recent.items) == 0) {
            s.silent_for = s.params.silence_rounds;
            s.recent.clearRetainingCapacity();
        }
    }
};

test "suffix lookup copies the continuation after a repeated n-gram" {
    const gpa = std.testing.allocator;
    var s = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2 });
    defer s.deinit();
    const ctx = [_]u32{ 1, 2, 3, 4, 5, 9, 1, 2, 3 };
    const got = try s.propose(&ctx, 3);
    try std.testing.expectEqualSlices(u32, &.{ 4, 5, 9 }, got);
    try std.testing.expectEqual(@as(i64, 3), s.last_match);
}

test "a resync proposes the source past a one-token edit, realigns on the tokens written, and gives up bounded" {
    const gpa = std.testing.allocator;
    var s = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true });
    defer s.deinit();
    // the source 1 2 3 4 5 6 7 8, copied so far as 1 2 3 (the suffix matches at index 3: the continuation 4 5 6 7 8)
    var ctx: std.ArrayList(u32) = .empty;
    defer ctx.deinit(gpa);
    try ctx.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    try std.testing.expectEqualSlices(u32, &.{ 4, 5, 6, 7, 8 }, try s.propose(ctx.items, 5));
    try std.testing.expect(!s.last_resync);
    // the target kept 4 and 5, then said 50 for 6 (a substitution): the context grew by the kept rows and 50
    try s.observe(5, 2);
    try ctx.appendSlice(gpa, &.{ 4, 5, 50 });
    // no suffix ends in (5, 50): the resync proposes the source past the replaced 6, passing the entry gate
    try std.testing.expectEqualSlices(u32, &.{ 7, 8, 9, 1, 2 }, try s.propose(ctx.items, 5));
    try std.testing.expect(s.last_resync);
    try std.testing.expect(s.last_match >= 24);
    // the same proposal again on the same context (the planner probes, then plans), at the width asked
    try std.testing.expectEqualSlices(u32, &.{ 7, 8 }, try s.propose(ctx.items, 2));
    // kept whole: the run ends, nothing pends
    try s.observe(2, 2);
    try ctx.appendSlice(gpa, &.{ 7, 8, 60 });
    try std.testing.expectEqual(@as(usize, 0), (try s.propose(ctx.items, 5)).len);
    try std.testing.expectEqual(@as(?usize, null), s.resync_miss);
    // a deletion: copying 1 2 3, the target skips 4 and says 5 at once -> the source resumes at 6
    var t = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true, .resync_min_kept = 0 });
    defer t.deinit();
    var c2: std.ArrayList(u32) = .empty;
    defer c2.deinit(gpa);
    try c2.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try t.propose(c2.items, 3); // 4 5 6
    try t.observe(3, 0); // 4 rejected: the target said 5
    try c2.append(gpa, 5);
    try std.testing.expectEqualSlices(u32, &.{ 6, 7, 8 }, try t.propose(c2.items, 3));
    // a resync that landed nothing spends a try and keeps the miss; the target still inside its edit gets no
    // proposal; once its last token is found just past the miss, the source resumes there
    try t.observe(3, 0); // the resync's 6 rejected: the target said 70 (a replacement longer than one token)
    try std.testing.expectEqual(@as(u32, 1), t.resync_tried);
    try c2.appendSlice(gpa, &.{ 70, 71 });
    try std.testing.expectEqual(@as(usize, 0), (try t.propose(c2.items, 3)).len);
    try c2.append(gpa, 6); // the target is back on the source: the last token written sits at the miss + 2
    try std.testing.expectEqualSlices(u32, &.{ 7, 8, 9 }, try t.propose(c2.items, 3));
    try std.testing.expect(t.last_resync);
    // an insertion: copying 1 2 3, the target writes 50 then the source's own 4: the guess past 4 misses, the next
    // token written (4) is found at the miss, and the source resumes at 5
    var u = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true, .resync_min_kept = 0 });
    defer u.deinit();
    var c3: std.ArrayList(u32) = .empty;
    defer c3.deinit(gpa);
    try c3.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try u.propose(c3.items, 3); // 4 5 6
    try u.observe(3, 0);
    try c3.append(gpa, 50);
    try std.testing.expectEqualSlices(u32, &.{ 5, 6, 7 }, try u.propose(c3.items, 3)); // the substitution guess
    try u.observe(3, 0); // wrong: the target said 4
    try c3.append(gpa, 4);
    try std.testing.expectEqualSlices(u32, &.{ 5, 6, 7 }, try u.propose(c3.items, 3));
    try u.observe(3, 3);
    try std.testing.expectEqual(@as(?usize, null), u.resync_miss);
    // tries are bounded: two resyncs landing nothing end the resync for that miss
    var v = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true, .resync_min_kept = 0 });
    defer v.deinit();
    var c4: std.ArrayList(u32) = .empty;
    defer c4.deinit(gpa);
    try c4.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try v.propose(c4.items, 3);
    try v.observe(3, 0);
    try c4.append(gpa, 50);
    _ = try v.propose(c4.items, 3); // the guess (5 6 7)
    try v.observe(3, 0);
    try c4.append(gpa, 6); // found near the miss: 7 8 9
    try std.testing.expectEqualSlices(u32, &.{ 7, 8, 9 }, try v.propose(c4.items, 3));
    try v.observe(3, 0);
    try c4.append(gpa, 8);
    try std.testing.expectEqual(@as(usize, 0), (try v.propose(c4.items, 3)).len);
    try std.testing.expectEqual(@as(i64, 0), v.silent_for); // resync misses never silence the proposer
}

test "a resync is armed only by a copy that was landing" {
    const gpa = std.testing.allocator;
    var s = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true });
    defer s.deinit();
    var ctx: std.ArrayList(u32) = .empty;
    defer ctx.deinit(gpa);
    try ctx.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    // a coincidental match the target leaves at once: no resync, the next proposal needs a suffix match again
    _ = try s.propose(ctx.items, 3);
    try s.observe(3, 1);
    try ctx.appendSlice(gpa, &.{ 4, 50 });
    try std.testing.expectEqual(@as(?usize, null), s.resync_miss);
    try std.testing.expectEqual(@as(usize, 0), (try s.propose(ctx.items, 3)).len);
    // a copy that landed two rows before the edit arms one
    var t = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true });
    defer t.deinit();
    var c2: std.ArrayList(u32) = .empty;
    defer c2.deinit(gpa);
    try c2.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try t.propose(c2.items, 3);
    try t.observe(3, 2);
    try c2.appendSlice(gpa, &.{ 4, 5, 50 });
    try std.testing.expectEqualSlices(u32, &.{ 7, 8, 9 }, try t.propose(c2.items, 3));
}

test "a resync is armed only by a copy out of the prompt" {
    const gpa = std.testing.allocator;
    // the prompt is the first 9 tokens; the reply copies them, then an edit
    var s = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true, .resync_source_end = 9 });
    defer s.deinit();
    var ctx: std.ArrayList(u32) = .empty;
    defer ctx.deinit(gpa);
    try ctx.appendSlice(gpa, &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try s.propose(ctx.items, 3); // 4 5 6 out of the prompt
    try s.observe(3, 2);
    try ctx.appendSlice(gpa, &.{ 4, 5, 50 });
    try std.testing.expectEqualSlices(u32, &.{ 7, 8, 9 }, try s.propose(ctx.items, 3));
    // a reply repeating its own lines (the source past the prompt) never resyncs
    var t = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2, .resync = true, .resync_source_end = 2 });
    defer t.deinit();
    var c2: std.ArrayList(u32) = .empty;
    defer c2.deinit(gpa);
    try c2.appendSlice(gpa, &.{ 0, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 1, 2, 3 });
    _ = try t.propose(c2.items, 3);
    try t.observe(3, 2);
    try c2.appendSlice(gpa, &.{ 4, 5, 50 });
    try std.testing.expectEqual(@as(?usize, null), t.resync_miss);
    try std.testing.expectEqual(@as(usize, 0), (try t.propose(c2.items, 3)).len);
}

/// The round loop's gate on a copy (windows.copyProposal): at least two tokens backed by `enter_match` (8).
fn gated(s: *const SuffixLookup, got: []const u32) []const u32 {
    return if (got.len < 2 or s.last_match < 8) &.{} else got;
}

test "raising min_match to the round loop's enter_match changes only the resyncs it lets through" {
    // lane_host.zig: with resyncs on, the proposer's min_match is max(min_match, enter_match) = 8 (stock 4). The round
    // loop drops every copy under enter_match and the longest match does not depend on min_match, so two proposers
    // that differ only in min_match 4 / 8 feed the loop the same copies until the min_match-8 one resyncs where the
    // other returned a 4-7 token match the loop drops. Rounds on contexts of copied spans with edits and noise: the
    // target keeps a copy's rows up to its first miss, then writes its own token (the loop's observe).
    const gpa = std.testing.allocator;
    var prng = std.Random.DefaultPrng.init(4408);
    const r = prng.random();
    for ([_]bool{ false, true }) |resync| {
        var diverged: usize = 0;
        var copies: usize = 0;
        for (0..16) |trial| {
            var lo = try SuffixLookup.init(gpa, .{ .min_match = 4, .resync = resync });
            defer lo.deinit();
            var hi = try SuffixLookup.init(gpa, .{ .min_match = 8, .resync = resync });
            defer hi.deinit();
            var ctx: std.ArrayList(u32) = .empty;
            defer ctx.deinit(gpa);
            for (0..200) |_| try ctx.append(gpa, r.uintLessThan(u32, 24 + 8 * @as(u32, @intCast(trial % 8))));
            var from: usize = r.uintLessThan(usize, 150);
            while (ctx.items.len < 2000) {
                const a = gated(&lo, try lo.propose(ctx.items, 15));
                const b = gated(&hi, try hi.propose(ctx.items, 15));
                if (!std.mem.eql(u32, a, b)) {
                    // the first difference: the min_match-8 proposer's resync where the other's match was dropped
                    try std.testing.expect(resync and hi.last_resync and a.len == 0);
                    diverged += 1;
                    break;
                }
                // the target's next tokens: mostly the copied source, sometimes an edit (a token of its own, the
                // source resumed), sometimes a jump to another source
                var fut: [16]u32 = undefined;
                var froms: [16]usize = undefined;
                var f = from;
                for (&fut, &froms) |*x, *fr| {
                    const u = r.uintLessThan(u32, 20);
                    if (u < 17 and f + 1 < ctx.items.len) {
                        f += 1;
                        x.* = ctx.items[f];
                    } else {
                        x.* = r.uintLessThan(u32, 64);
                        if (u == 19) f = r.uintLessThan(usize, ctx.items.len - 1);
                    }
                    fr.* = f;
                }
                var kept: usize = 0;
                while (kept < a.len and kept < fut.len - 1 and a[kept] == fut[kept]) kept += 1;
                if (a.len > 0) {
                    copies += 1;
                    try lo.observe(@intCast(a.len), @intCast(kept));
                    try hi.observe(@intCast(b.len), @intCast(kept));
                }
                try ctx.appendSlice(gpa, fut[0 .. kept + 1]);
                from = froms[kept];
            }
        }
        try std.testing.expect(copies > 200); // the rounds verify copies
        // without resyncs the two never differ; with them they do, and only by a resync (asserted above)
        if (resync) try std.testing.expect(diverged > 0) else try std.testing.expectEqual(@as(usize, 0), diverged);
    }
}

test "lastFrom answers for the latest proposal only: null after an empty one" {
    const gpa = std.testing.allocator;
    var s = try SuffixLookup.init(gpa, .{ .ngram = 2, .min_match = 2 });
    defer s.deinit();
    const p = s.proposer();
    try std.testing.expectEqual(@as(?usize, null), p.lastFrom());
    const ctx = [_]u32{ 1, 2, 3, 4, 5, 9, 1, 2, 3 };
    try std.testing.expectEqualSlices(u32, &.{ 4, 5, 9 }, try s.propose(&ctx, 3));
    try std.testing.expectEqual(@as(?usize, 3), p.lastFrom());
    // no match: the proposal is empty, and so is its source (not the previous proposal's)
    const other = [_]u32{ 1, 2, 3, 4, 5, 9, 1, 2, 3, 77, 78 };
    try std.testing.expectEqual(@as(usize, 0), (try s.propose(&other, 3)).len);
    try std.testing.expectEqual(@as(?usize, null), p.lastFrom());
    // and a later match answers again
    try std.testing.expectEqualSlices(u32, &.{ 4, 5, 9 }, try s.propose(&ctx, 3));
    try std.testing.expectEqual(@as(?usize, 3), p.lastFrom());
}
