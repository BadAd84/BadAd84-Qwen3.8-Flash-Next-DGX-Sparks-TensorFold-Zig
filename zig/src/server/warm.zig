//! After a chat reply, the next turn's shared prompt prefilled in the background, so that turn resumes past the reply
//! (TensorFold main's server/warm.zig, 34c44245 and 924104e2, on this server's chat path). The request is prompt-only
//! (max_tokens 0) and background: the lane host runs it only on an idle engine (LaneHost.warmPass), and the prompt
//! cache keeps its whole-prompt state, which the next turn's prompt extends token for token or not at all.
const std = @import("std");
const api = @import("engine_api");
const json = @import("json.zig");
const errors = @import("errors.zig");
const fields_mod = @import("fields.zig");
const prompt_mod = @import("prompt.zig");
const chat = @import("chat.zig");
const log = @import("log.zig");
const Server = @import("server.zig").Server;
const Value = json.Value;

/// One background prompt pass and the arena holding its request until the engine finishes it.
const Pass = struct {
    gpa: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    request: api.Request,

    fn event(ptr: *anyopaque, _: api.Id, e: *const api.Event) void {
        if (e.* != .finished) return;
        const p: *Pass = @ptrCast(@alignCast(ptr));
        var arena = p.arena;
        p.gpa.destroy(p);
        arena.deinit();
    }
};

/// Prefill the conversation, `message` (the reply as its client got it) and the next turn's opening, on a
/// warm_turns engine. Token prompts, image and video requests and other templates' failures take no pass.
pub fn reply(srv: *Server, input: chat.Input, message: Value, thinking: bool, effort: ?[]const u8) void {
    if (!srv.info.warm_turns or input.prompt != null or input.media != null or input.messages != .array) return;
    start(srv, input, message, thinking, effort) catch |e| log.line("next turn: no background prefill ({s})", .{@errorName(e)});
}

fn start(srv: *Server, input: chat.Input, message: Value, thinking: bool, effort: ?[]const u8) !void {
    const p = try srv.gpa.create(Pass);
    p.* = .{ .gpa = srv.gpa, .arena = .init(srv.gpa), .request = undefined };
    var handed = false;
    defer if (!handed) {
        p.arena.deinit();
        srv.gpa.destroy(p);
    };
    const a = p.arena.allocator();
    var cx: errors.Cx = .{ .a = a };
    const prompt = try shared(srv, &cx, input, message, thinking, effort);
    if (prompt.len == 0 or (srv.info.context_window > 0 and prompt.len >= srv.info.context_window)) return;
    // the conversation's own salt: a state kept under another salt serves no request of this conversation
    const salt = fields_mod.cacheSalt(&cx, input.fields) catch return;
    p.request = .{ .prompt = prompt, .max_tokens = 0, .eos = srv.eos, .drafts = false, .background = true, .history_len = @intCast(prompt.len), .cache_salt = salt };
    const id = srv.next_id.fetchAdd(1, .monotonic);
    try srv.engine.submit(id, &p.request, .{ .ctx = p, .event = Pass.event });
    handed = true;
}

/// The tokens every next user turn shares: the conversation and the reply rendered twice, with a probe user message
/// "A" and then "B" after them; the renderings agree up to that message's text.
fn shared(srv: *Server, cx: *errors.Cx, input: chat.Input, message: Value, thinking: bool, effort: ?[]const u8) ![]const u32 {
    const before = input.messages.array;
    var ids: [2][]const u32 = undefined;
    for ([_][]const u8{ "A", "B" }, &ids) |text, *out| {
        const list = try cx.a.alloc(Value, before.len + 2);
        @memcpy(list[0..before.len], before);
        list[before.len] = message;
        const user = try json.newObject(cx.a);
        try user.put(cx.a, "role", .{ .string = "user" });
        try user.put(cx.a, "content", .{ .string = text });
        list[before.len + 1] = .{ .object = user };
        out.* = try prompt_mod.renderIds(srv, cx, .{ .array = list }, input.tools, thinking, effort, true);
    }
    const n = std.mem.indexOfDiff(u32, ids[0], ids[1]) orelse return &.{};
    return ids[0][0..n];
}
