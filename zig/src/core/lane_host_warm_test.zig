//! LaneHost warm passes (Info.warm_turns, server/warm.zig): a prompt-only background request on an idle engine keeps
//! the next turn's prefix, and that turn resumes past it with the tokens a cold pass draws (the fake backend).
const std = @import("std");
const lanes = @import("lanes");
const api = @import("engine_api.zig");
const pc = @import("prompt_cache.zig");
const LaneHost = api.LaneHost;
const Id = api.Id;
const Event = api.Event;
const Request = api.Request;
const Reason = api.Reason;

const gpa = std.testing.allocator;

const Snaps = struct {
    fn bytes(_: *anyopaque, at: u32) u64 {
        return 64 + 4 * @as(u64, at);
    }
    fn save(ptr: *anyopaque, owner: ?*anyopaque, at: u32) anyerror!pc.Saved {
        const f: *lanes.fake.Fake = @ptrCast(@alignCast(ptr));
        return f.save(@ptrCast(@alignCast(owner.?)), at);
    }
    fn restore(_: *anyopaque, _: ?*anyopaque, _: pc.Saved) anyerror!void {
        return error.BackendRestores;
    }
    fn drop(ptr: *anyopaque, saved: pc.Saved) void {
        const f: *lanes.fake.Fake = @ptrCast(@alignCast(ptr));
        f.drop(saved);
    }
};

const Box = struct {
    mutex: std.Io.Mutex = .init,
    tokens: std.ArrayList(u32) = .empty,
    cached: ?u32 = null,
    done: ?Reason = null,
    fn event(ctx: *anyopaque, _: Id, e: *const Event) void {
        const b: *@This() = @ptrCast(@alignCast(ctx));
        b.mutex.lockUncancelable(std.testing.io);
        defer b.mutex.unlock(std.testing.io);
        switch (e.*) {
            .prefilled => |c| b.cached = c,
            .tokens => |t| b.tokens.appendSlice(gpa, t) catch {},
            .finished => |f| b.done = f.reason,
        }
    }
    fn wait(b: *@This()) Reason {
        while (true) {
            b.mutex.lockUncancelable(std.testing.io);
            const d = b.done;
            b.mutex.unlock(std.testing.io);
            if (d) |r| return r;
            std.Io.sleep(std.testing.io, .fromMilliseconds(1), .awake) catch {};
        }
    }
};

test "a warm pass keeps the next turn's prefix on an idle engine, and that turn resumes past it with a cold pass's tokens" {
    var cfg = try lanes.Config.init(gpa, .{ .exact_width = 8, .gpu_tokens = true, .hidden_rows = true }, 8, 7);
    defer cfg.deinit(gpa);
    var target: lanes.fake.Fake = .{ .gpa = gpa };
    defer target.deinit();
    var clock: lanes.fake.FixedClock = .{};
    var core = lanes.Engine.init(gpa, &cfg, target.backend(), clock.clock());
    defer core.deinit();
    var store = pc.Store.init(gpa, .{ .ptr = &target, .vtable = &.{ .bytes = Snaps.bytes, .save = Snaps.save, .restore = Snaps.restore, .drop = Snaps.drop } }, .{ .min_prompt = 64, .whole = true, .whole_min = 4 }, 1 << 20);
    defer store.deinit();
    var host = LaneHost.init(gpa, std.testing.io, &core, .{ .lanes = 2, .warm_turns = true });
    host.cache = &store;
    host.warm_delay_ns = 0;
    try host.start();
    defer host.stop();
    const e = host.engine();
    const turn = [_]u32{ 3, 1, 4, 1, 5, 9, 2, 6, 5, 3 }; // the first turn
    const warm = turn ++ [_]u32{ 7, 7, 8 }; // the conversation, its reply and the next turn's opening
    const next = warm ++ [_]u32{ 2, 4 }; // the next turn
    var b0: Box = .{};
    defer b0.tokens.deinit(gpa);
    try e.submit(1, &.{ .prompt = &turn, .max_tokens = 4 }, .{ .ctx = &b0, .event = Box.event });
    try std.testing.expectEqual(Reason.length, b0.wait());
    // the warm pass: prompt-only, background; it resumes the first turn's whole state, keeps its own, draws nothing
    var bw: Box = .{};
    defer bw.tokens.deinit(gpa);
    const wr: Request = .{ .prompt = &warm, .max_tokens = 0, .background = true, .history_len = warm.len };
    try e.submit(2, &wr, .{ .ctx = &bw, .event = Box.event });
    try std.testing.expectEqual(Reason.length, bw.wait());
    try std.testing.expectEqual(@as(?u32, turn.len), bw.cached);
    try std.testing.expectEqual(@as(usize, 0), bw.tokens.items.len);
    try std.testing.expectEqual(@as(usize, 0), target.lanes.count()); // the pass released its lane (its state is kept)
    // the next turn resumes at the warm prompt's end; a cold pass of it (another salt) draws the same tokens
    var bn: Box = .{};
    defer bn.tokens.deinit(gpa);
    try e.submit(3, &.{ .prompt = &next, .max_tokens = 6 }, .{ .ctx = &bn, .event = Box.event });
    try std.testing.expectEqual(Reason.length, bn.wait());
    try std.testing.expectEqual(@as(?u32, warm.len), bn.cached);
    var bc: Box = .{};
    defer bc.tokens.deinit(gpa);
    try e.submit(4, &.{ .prompt = &next, .max_tokens = 6, .cache_salt = pc.saltKey("cold") }, .{ .ctx = &bc, .event = Box.event });
    try std.testing.expectEqual(Reason.length, bc.wait());
    try std.testing.expectEqual(@as(?u32, 0), bc.cached);
    try std.testing.expectEqualSlices(u32, bc.tokens.items, bn.tokens.items);
}

test "a warm pass steps aside: a foreground request queued before it is due ends it unrun" {
    var cfg = try lanes.Config.init(gpa, .{ .exact_width = 8, .gpu_tokens = true, .hidden_rows = true }, 8, 7);
    defer cfg.deinit(gpa);
    var target: lanes.fake.Fake = .{ .gpa = gpa };
    defer target.deinit();
    var clock: lanes.fake.FixedClock = .{};
    var core = lanes.Engine.init(gpa, &cfg, target.backend(), clock.clock());
    defer core.deinit();
    var store = pc.Store.init(gpa, .{ .ptr = &target, .vtable = &.{ .bytes = Snaps.bytes, .save = Snaps.save, .restore = Snaps.restore, .drop = Snaps.drop } }, .{ .min_prompt = 64, .whole = true, .whole_min = 4 }, 1 << 20);
    defer store.deinit();
    var host = LaneHost.init(gpa, std.testing.io, &core, .{ .lanes = 2, .warm_turns = true });
    host.cache = &store;
    host.warm_delay_ns = 60 * std.time.ns_per_s; // never due within the test
    try host.start();
    defer host.stop();
    const e = host.engine();
    const warm = [_]u32{ 3, 1, 4, 1, 5, 9, 2, 6 };
    const other = [_]u32{ 2, 7, 1, 8, 2, 8 };
    var bw: Box = .{};
    defer bw.tokens.deinit(gpa);
    try e.submit(1, &.{ .prompt = &warm, .max_tokens = 0, .background = true, .history_len = warm.len }, .{ .ctx = &bw, .event = Box.event });
    std.Io.sleep(std.testing.io, .fromMilliseconds(50), .awake) catch {}; // not due yet: an idle engine leaves it queued
    var bf: Box = .{};
    defer bf.tokens.deinit(gpa);
    try e.submit(2, &.{ .prompt = &other, .max_tokens = 3 }, .{ .ctx = &bf, .event = Box.event });
    try std.testing.expectEqual(Reason.length, bf.wait());
    try std.testing.expectEqual(Reason.cancelled, bw.wait());
    try std.testing.expectEqual(@as(?u32, null), bw.cached); // it never ran a pass
    try std.testing.expectEqual(@as(usize, 1), store.entries.items.len); // the foreground prompt's whole state alone
}

test "a warm pass whose whole-prompt state the budget refuses ends unrun: it would keep nothing" {
    var cfg = try lanes.Config.init(gpa, .{ .exact_width = 8, .gpu_tokens = true, .hidden_rows = true }, 8, 7);
    defer cfg.deinit(gpa);
    var target: lanes.fake.Fake = .{ .gpa = gpa };
    defer target.deinit();
    var clock: lanes.fake.FixedClock = .{};
    var core = lanes.Engine.init(gpa, &cfg, target.backend(), clock.clock());
    defer core.deinit();
    // 100 bytes: Snaps.bytes(8) is 96 (fits), Snaps.bytes(13) is 116 (refused by the store's fitting)
    var store = pc.Store.init(gpa, .{ .ptr = &target, .vtable = &.{ .bytes = Snaps.bytes, .save = Snaps.save, .restore = Snaps.restore, .drop = Snaps.drop } }, .{ .min_prompt = 64, .whole = true, .whole_min = 4 }, 100);
    defer store.deinit();
    var host = LaneHost.init(gpa, std.testing.io, &core, .{ .lanes = 2, .warm_turns = true });
    host.cache = &store;
    host.warm_delay_ns = 0;
    try host.start();
    defer host.stop();
    const e = host.engine();
    const warm = [_]u32{ 3, 1, 4, 1, 5, 9, 2, 6, 5, 3, 5, 8, 9 };
    var bw: Box = .{};
    defer bw.tokens.deinit(gpa);
    try e.submit(1, &.{ .prompt = &warm, .max_tokens = 0, .background = true, .history_len = warm.len }, .{ .ctx = &bw, .event = Box.event });
    try std.testing.expectEqual(Reason.cancelled, bw.wait());
    try std.testing.expectEqual(@as(?u32, null), bw.cached); // no prompt pass ran
    try std.testing.expectEqual(@as(usize, 0), store.entries.items.len);
}
