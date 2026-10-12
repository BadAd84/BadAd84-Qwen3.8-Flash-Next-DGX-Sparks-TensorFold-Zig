//! Exact prompt reuse for any family and backend: states kept at prompt-pass chunk ends (and, for families that can,
//! at a prompt's end with its last logits row), found by their tokens and the request's cache salt.
const std = @import("std");
const Allocator = std.mem.Allocator;

/// A family's copy of one state.
pub const Saved = *anyopaque;

/// What a family gives the cache: copies of its state while the prompt pass stands at a chunk end.
pub const Snapshots = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// The most new storage `save` takes at `at` tokens (checked against the budget before any copy).
        bytes: *const fn (ptr: *anyopaque, at: u32) u64,
        /// Copy the live state after `at` prompt tokens into new storage; `owner` is the lane core's stream (null: one stream).
        save: *const fn (ptr: *anyopaque, owner: ?*anyopaque, at: u32) anyerror!Saved,
        /// Make the live state `saved`'s: the next prompt chunk starts at its position.
        restore: *const fn (ptr: *anyopaque, owner: ?*anyopaque, saved: Saved) anyerror!void,
        drop: *const fn (ptr: *anyopaque, saved: Saved) void,
        /// The storage a kept state holds: new storage up to `bytes`, or the spare storage it took (null: `bytes`).
        charged: ?*const fn (ptr: *anyopaque, saved: Saved) u64 = null,
        /// Free storage the family keeps for later saves, inside the budget (null: none).
        spare: ?*const fn (ptr: *anyopaque) u64 = null,
        /// Free spare storage until at most `room` bytes stay spare.
        trim: ?*const fn (ptr: *anyopaque, room: u64) void = null,
        /// Whether a save at `at` would take spare storage (no new storage).
        reuses: ?*const fn (ptr: *anyopaque, at: u32) bool = null,
    };
};

/// What a family's states depend on beyond their position.
pub const Rules = struct {
    /// Tokens past the position a state read (Flash Next's MTP head keys row at-1 with token at: 1).
    lookahead: u32 = 0,
    /// Prompt kernels that change arithmetic with a chunk's rows: resume and keep only at the request's chunk starts.
    planned: bool = false,
    /// A mark other than the history's is kept only this far from every other mark and the resume point.
    min_gap: u32 = 256,
    /// Shorter prompts keep no mark inside them: below it a mark's extra prompt call costs more than a later turn's
    /// reuse saves (the whole-prompt state below makes no extra call).
    min_prompt: u32 = 4096,
    /// The family keeps a prompt's state at its END with the prompt's last logits row, and resumes the very same prompt
    /// from it with no forward (a replay draws its first token from the kept row) or a longer one as from any state.
    /// Such a state costs the pass no extra prompt call, so it is kept below min_prompt too. Needs `lookahead` 0 and
    /// an unplanned family (the prompt's end is no chunk start).
    whole: bool = false,
    /// The shortest prompt whose whole-prompt state is kept.
    whole_min: u32 = 1024,
};

/// A request's cache salt (vLLM's `cache_salt`) as the store keys it: 0 for none. A salted request resumes only
/// states its own salt kept, so a fresh salt is a fresh prefill; the unsalted share theirs as before.
pub fn saltKey(salt: ?[]const u8) u64 {
    const s = salt orelse return 0;
    const k = std.hash.Wyhash.hash(0x5a17, s);
    return if (k == 0) 1 else k;
}

/// `rules` with whole-prompt states as the settings ask: `whole` (TENSORFOLD_PROMPT_CACHE_WHOLE) "1" keeps them, unset
/// or "0" keeps none; `min` (TENSORFOLD_PROMPT_CACHE_WHOLE_MIN) the shortest prompt that keeps one, 1 .. 2^32 - 1
/// (unset: Rules.whole_min). Any other value is refused (error.BadSetting, logged with the setting's name), and so is
/// "1" for a family that cannot resume a prompt's very end (`can`), never read as on or off.
pub fn wholeRules(rules: Rules, can: bool, whole: ?[]const u8, min: ?[]const u8) !Rules {
    var r = rules;
    r.whole = false;
    if (whole) |v| {
        if (std.mem.eql(u8, v, "1")) {
            if (!can) {
                std.log.warn("TENSORFOLD_PROMPT_CACHE_WHOLE=1 refused: this engine keeps no whole-prompt states", .{});
                return error.BadSetting;
            }
            r.whole = true;
        } else if (!std.mem.eql(u8, v, "0")) {
            std.log.warn("TENSORFOLD_PROMPT_CACHE_WHOLE={s} refused: 0 (none) or 1 (whole-prompt states)", .{v});
            return error.BadSetting;
        }
    }
    if (min) |v| {
        const n = std.fmt.parseInt(u32, v, 10) catch 0;
        if (n == 0) {
            std.log.warn("TENSORFOLD_PROMPT_CACHE_WHOLE_MIN={s} refused: the shortest prompt kept whole, 1 .. 4294967295 tokens", .{v});
            return error.BadSetting;
        }
        r.whole_min = n;
    }
    return r;
}

pub const Entry = struct {
    tokens: []u32, // the state's tokens and `lookahead` more
    at: u32,
    saved: Saved,
    bytes: u64,
    born: u32, // the length of the prompt that kept it: a later turn's is longer
    used: u64, // the store's clock at its last keep or resume
    last: []u32, // the last prompt that kept or resumed it
    shared: bool = false, // kept at a shared system block's cut: other conversations resume it, so its own never supersedes it
    salt: u64 = 0, // the cache salt of the request that kept it (saltKey): only the same salt resumes it
    short: bool = false, // kept for a prompt under min_prompt (its whole-prompt state): such a prompt frees only these (victimBut)
    whole: bool = false, // kept at its prompt's end (Rules.whole): the same prompt resumes it with no forward
    branched: bool = false, // resumed after a longer state of its salt extended it: a turn several continuations share
    // (a re-sent or forked turn), so none of them supersedes it (victimBut)
};

pub const Counts = struct { hits: u64 = 0, misses: u64 = 0, kept: u64 = 0, evicted: u64 = 0, refused: u64 = 0, failed: u64 = 0 };

/// Where a prompt pass starts and where it stops to keep its state (marks sorted, in `a`).
pub const Plan = struct { from: u32 = 0, marks: []const u32 = &.{} };

/// The entry a backend restores itself (null: the pass starts at 0) and the pass's marks.
pub const Lookup = struct { entry: ?*Entry = null, marks: []const u32 = &.{} };

pub const Store = struct {
    gpa: Allocator,
    family: Snapshots,
    rules: Rules,
    budget: u64,
    held: u64 = 0,
    clock: u64 = 0,
    entries: std.ArrayList(*Entry) = .empty,
    counts: Counts = .{},
    shared_keys: std.ArrayList(u64) = .empty, // the tokens of recently planned shared cuts, hashed (at most SHARED_KEYS)

    const SHARED_KEYS = 64;

    pub fn init(gpa: Allocator, family: Snapshots, rules: Rules, budget: u64) Store {
        return .{ .gpa = gpa, .family = family, .rules = rules, .budget = budget };
    }

    pub fn deinit(s: *Store) void {
        for (s.entries.items) |e| s.free(e);
        s.entries.deinit(s.gpa);
        s.shared_keys.deinit(s.gpa);
        s.held = 0;
    }

    fn free(s: *Store, e: *Entry) void {
        s.family.vtable.drop(s.family.ptr, e.saved);
        s.gpa.free(e.tokens);
        s.gpa.free(e.last);
        s.gpa.destroy(e);
    }

    fn remove(s: *Store, i: usize) void {
        const e = s.entries.orderedRemove(i);
        s.held -= e.bytes;
        s.free(e);
    }

    /// The family's free storage kept for later saves.
    pub fn spare(s: *const Store) u64 {
        return if (s.family.vtable.spare) |f| f(s.family.ptr) else 0;
    }

    /// What the budget leaves past the kept states and the spare storage: a family readies storage only inside it.
    pub fn room(s: *const Store) u64 {
        return s.budget -| s.held -| s.spare();
    }

    /// Whether a state at `at` may start or end a prompt pass: anywhere, or a chunk start for planned families.
    fn usable(s: *const Store, at: u32, starts: []const u32) bool {
        return at > 0 and (!s.rules.planned or std.mem.indexOfScalar(u32, starts, at) != null);
    }

    /// The longest kept state `prompt` resumes exactly under `salt` (saltKey): its tokens a prefix of the prompt, at
    /// least one row left, or (a whole-prompt state) the very prompt.
    pub fn find(s: *Store, prompt: []const u32, starts: []const u32, salt: u64) ?*Entry {
        var best: ?*Entry = null;
        for (s.entries.items) |e| {
            if (e.salt != salt or e.tokens.len > prompt.len or !s.usable(e.at, starts)) continue;
            if (e.at > prompt.len or (e.at == prompt.len and !e.whole)) continue;
            if (best != null and e.at <= best.?.at) continue;
            const n = e.tokens.len;
            if (prompt[n - 1] != e.tokens[n - 1] or !std.mem.eql(u32, prompt[0..n], e.tokens)) continue;
            best = e;
        }
        return best;
    }

    /// Before a prompt pass: restore the longest state `prompt` resumes (from 0: none or a failed copy) and plan its marks.
    pub fn begin(s: *Store, a: Allocator, prompt: []const u32, history_len: u32, shared: []const u32, starts: []const u32, owner: ?*anyopaque, salt: u64) !Plan {
        const l = try s.lookup(a, prompt, history_len, shared, starts, salt);
        const e = l.entry orelse return .{ .marks = l.marks };
        const ok = if (s.family.vtable.restore(s.family.ptr, owner, e.saved)) |_| true else |err| blk: {
            note("restoring {d} tokens failed ({s}); prefilling from the start", .{ e.at, @errorName(err) });
            break :blk false;
        };
        const from = if (ok) e.at else 0;
        s.resumed(e, prompt, ok);
        _ = s.reserve(prompt, null, l.marks, salt); // restored: the state it resumed may go too (a peer restores before it drops)
        return .{ .from = from, .marks = l.marks };
    }

    /// begin without the restore, for backends that restore inside their own prompt pass and then call `resumed`.
    pub fn lookup(s: *Store, a: Allocator, prompt: []const u32, history_len: u32, shared: []const u32, starts: []const u32, salt: u64) !Lookup {
        const e = s.find(prompt, starts, salt);
        if (e == null) s.counts.misses += 1;
        var marks_ = try s.fitting(a, try s.marks(a, prompt, if (e) |x| x.at else 0, history_len, shared, starts, if (e) |x| x.last else &.{}));
        for (shared) |w| { // the shared cuts this pass keeps: their states serve other conversations too
            const at = if (s.rules.planned) floorStart(starts, w) else w;
            if (std.mem.indexOfScalar(u32, marks_, at) != null) s.noteShared(prompt[0 .. at + s.rules.lookahead], salt);
        }
        if (!s.reserve(prompt, e, marks_, salt) and s.isShort(prompt.len)) { // no short state left to free: refused before the pass copies it
            s.counts.refused += marks_.len;
            a.free(marks_);
            marks_ = &.{};
        }
        return .{ .entry = e, .marks = marks_ };
    }

    /// Room for every state the pass keeps, made before it: a peer that mirrors the keeps hears of these evictions with
    /// the request. False: the budget lacks the room and no state may go for this prompt (victimBut).
    fn reserve(s: *Store, prompt: []const u32, from: ?*Entry, marks_: []const u32, salt: u64) bool {
        var need: u64 = 0;
        for (marks_) |at| need += s.family.vtable.bytes(s.family.ptr, at);
        if (s.held + need > s.budget and s.isShort(prompt.len) and !s.shortRoom(from, need)) return false; // none go in vain
        while (s.held + need > s.budget) {
            const i = s.victimBut(from, prompt, salt) orelse return false;
            s.remove(i);
            s.counts.evicted += 1;
        }
        return true;
    }

    /// A kept state a peer could not resume goes, so later prompts do not ask for it again.
    pub fn forget(s: *Store, prompt: []const u32, at: u32, salt: u64) void {
        for (s.entries.items, 0..) |e, i| if (e.at == at and e.salt == salt and e.tokens.len <= prompt.len and std.mem.eql(u32, e.tokens, prompt[0..e.tokens.len])) {
            s.counts.failed += 1;
            return s.remove(i);
        };
    }

    fn sharedKey(tokens: []const u32, salt: u64) u64 {
        return std.hash.Wyhash.hash(salt, std.mem.sliceAsBytes(tokens));
    }

    fn noteShared(s: *Store, tokens: []const u32, salt: u64) void {
        const k = sharedKey(tokens, salt);
        if (std.mem.indexOfScalar(u64, s.shared_keys.items, k) != null) return;
        if (s.shared_keys.items.len == SHARED_KEYS) _ = s.shared_keys.orderedRemove(0);
        s.shared_keys.append(s.gpa, k) catch {};
    }

    /// Where a whole-prompt state of `prompt` is kept (its end), or null: the family keeps none, or it is too short.
    pub fn wholeAt(s: *const Store, prompt: []const u32) ?u32 {
        if (!s.rules.whole or s.rules.lookahead != 0 or s.rules.planned) return null;
        if (prompt.len < s.rules.whole_min or prompt.len > std.math.maxInt(u32)) return null;
        return @intCast(prompt.len);
    }

    /// The marks whose state the budget can hold (a new slice in `a`); the rest are refused now, so no pass, nor a peer, copies them.
    fn fitting(s: *Store, a: Allocator, marks_: []const u32) ![]const u32 {
        defer a.free(marks_);
        var out: std.ArrayList(u32) = .empty;
        for (marks_) |at| {
            const bytes = s.family.vtable.bytes(s.family.ptr, at);
            if (bytes <= s.budget) try out.append(a, at) else {
                s.counts.refused += 1;
                note("kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget", .{ at, bytes >> 20, s.budget >> 20 });
            }
        }
        return out.toOwnedSlice(a);
    }

    /// A looked-up entry's restore went through (it is now the prompt's), or failed (dropped: the pass ran from 0).
    /// Resumed while a longer state of its salt already extends it, it is a branch point (Entry.branched).
    pub fn resumed(s: *Store, e: *Entry, prompt: []const u32, ok: bool) void {
        const i = std.mem.indexOfScalar(*Entry, s.entries.items, e) orelse return;
        if (!ok) {
            s.counts.failed += 1;
            return s.remove(i);
        }
        s.clock += 1;
        e.used = s.clock;
        e.branched = e.branched or s.extended(e);
        s.counts.hits += 1;
        const last = s.gpa.dupe(u32, prompt) catch return;
        s.gpa.free(e.last);
        e.last = last;
    }

    /// Where a pass from `from` keeps states: the history, then min_gap apart the stable prefix and shared blocks (none
    /// under min_prompt); then the prompt's end (Rules.whole) unless the pass resumes there or another mark is within
    /// min_gap of it (a chat prompt's history mark keeps that turn, as before).
    pub fn marks(s: *const Store, a: Allocator, prompt: []const u32, from: u32, history_len: u32, shared: []const u32, starts: []const u32, previous: []const u32) ![]const u32 {
        var out: std.ArrayList(u32) = .empty;
        if (prompt.len >= s.rules.min_prompt) {
            var want: std.ArrayList(u32) = .empty;
            defer want.deinit(a);
            try want.append(a, history_len);
            if (previous.len > 0) {
                const stable: u32 = @intCast(std.mem.indexOfDiff(u32, previous, prompt) orelse @min(previous.len, prompt.len));
                if (stable > 0 and stable < history_len and stable >= history_len / 2) try want.append(a, stable);
            }
            try want.appendSlice(a, shared);
            for (want.items, 0..) |w, k| {
                const at = if (s.rules.planned) floorStart(starts, w) else w;
                if (at <= from or at + s.rules.lookahead > prompt.len or at >= prompt.len or !s.usable(at, starts)) continue;
                if (k > 0) { // the history's mark always; the others only away from it, each other and the resume point
                    if (at - from < s.rules.min_gap) continue;
                    const near = for (out.items) |o| {
                        if (@max(o, at) - @min(o, at) < s.rules.min_gap) break true;
                    } else false;
                    if (near) continue;
                }
                if (std.mem.indexOfScalar(u32, out.items, at) == null) try out.append(a, at);
            }
        }
        if (s.wholeAt(prompt)) |at| if (at > from) {
            const near = for (out.items) |o| { // every other mark is inside the prompt: o < at
                if (at - o < s.rules.min_gap) break true;
            } else false;
            if (!near) try out.append(a, at);
        };
        std.mem.sort(u32, out.items, {}, std.sort.asc(u32));
        return out.toOwnedSlice(a);
    }

    /// The prompt pass stands at `at` (its end for a whole-prompt state): keep its state for `prompt` under `salt`,
    /// evicting to fit; refused (counted) past the budget.
    pub fn keep(s: *Store, prompt: []const u32, at: u32, owner: ?*anyopaque, salt: u64) bool {
        const n = @as(usize, at) + s.rules.lookahead;
        if (at == 0 or n > prompt.len) return false;
        s.clock += 1;
        const whole = s.wholeAt(prompt) != null and n == prompt.len;
        const shared = std.mem.indexOfScalar(u64, s.shared_keys.items, sharedKey(prompt[0..n], salt)) != null;
        for (s.entries.items, 0..) |e, i| if (e.at == at and e.salt == salt and std.mem.eql(u32, e.tokens, prompt[0..n])) {
            if (whole and !e.whole) { // the same state without the prompt's last row: the whole one replaces it
                s.remove(i);
                break;
            }
            e.used = s.clock; // the same state again: no copy
            e.shared = e.shared or shared;
            return true;
        };
        const bytes = s.family.vtable.bytes(s.family.ptr, at);
        if (bytes > s.budget) {
            s.counts.refused += 1;
            note("kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget", .{ at, bytes >> 20, s.budget >> 20 });
            return false;
        }
        while (s.entries.items.len > 0) { // room: spare storage this save can take, else new storage inside the budget
            if (s.family.vtable.reuses) |f| if (f(s.family.ptr, at)) break;
            const free_ = s.spare();
            if (s.held + free_ + bytes <= s.budget) break;
            if (free_ > 0) {
                if (s.family.vtable.trim) |f| f(s.family.ptr, s.budget -| s.held -| bytes); // spare that cannot take this state goes before any state
                if (s.spare() < free_) continue;
            }
            if (s.isShort(prompt.len) and !s.shortRoom(null, bytes)) { // a short prompt's state: too few short ones to free
                s.counts.refused += 1;
                return false;
            }
            const i = s.victimBut(null, prompt, salt) orelse { // a short prompt's: every short state gone, the family's spare still short of room
                s.counts.refused += 1;
                return false;
            };
            s.remove(i); // its storage may come back spare and take this state
            s.counts.evicted += 1;
        }
        if (s.entries.items.len == 0) if (s.family.vtable.trim) |f| f(s.family.ptr, s.budget -| bytes);
        const e = s.gpa.create(Entry) catch return s.fail(at, error.OutOfMemory);
        const tokens = s.gpa.dupe(u32, prompt[0..n]) catch {
            s.gpa.destroy(e);
            return s.fail(at, error.OutOfMemory);
        };
        const last = s.gpa.dupe(u32, prompt) catch {
            s.gpa.free(tokens);
            s.gpa.destroy(e);
            return s.fail(at, error.OutOfMemory);
        };
        const saved = s.family.vtable.save(s.family.ptr, owner, at) catch |err| {
            s.gpa.free(last);
            s.gpa.free(tokens);
            s.gpa.destroy(e);
            return s.fail(at, err);
        };
        const charged = if (s.family.vtable.charged) |f| f(s.family.ptr, saved) else bytes;
        e.* = .{ .tokens = tokens, .at = at, .saved = saved, .bytes = charged, .born = @intCast(prompt.len), .used = s.clock, .last = last, .shared = shared, .salt = salt, .short = s.isShort(prompt.len), .whole = whole };
        s.entries.append(s.gpa, e) catch {
            s.free(e);
            return s.fail(at, error.OutOfMemory);
        };
        s.held += charged;
        s.counts.kept += 1;
        if (s.family.vtable.trim) |f| f(s.family.ptr, s.budget -| s.held); // spare storage only inside what the budget leaves
        return true;
    }

    /// One log line after a prompt pass: where it resumed, how many states it kept, and what the store holds.
    pub fn report(s: *const Store, prompt: usize, from: u32, kept: u64) void {
        if (@import("builtin").is_test) return;
        std.log.info("prompt cache: {d} tokens, resumed at {d}, kept {d}; {d} states, {d} MiB and {d} MiB spare of {d} MiB (hits {d}, misses {d}, evicted {d}, refused {d}, failed {d})", .{ prompt, from, kept, s.entries.items.len, s.held >> 20, s.spare() >> 20, s.budget >> 20, s.counts.hits, s.counts.misses, s.counts.evicted, s.counts.refused, s.counts.failed });
    }

    fn fail(s: *Store, at: u32, err: anyerror) bool {
        defer s.counts.failed += 1;
        note("keeping {d} tokens failed ({s}); a later turn prefills them", .{ at, @errorName(err) });
        return false;
    }

    /// A prompt under min_prompt: it keeps only its whole-prompt state (Entry.short).
    fn isShort(s: *const Store, len: usize) bool {
        return len < s.rules.min_prompt;
    }

    /// Whether a longer prompt of `e`'s salt kept a state that extends it (a later turn of its conversation).
    fn extended(s: *const Store, e: *const Entry) bool {
        for (s.entries.items) |o| {
            if (o != e and o.salt == e.salt and o.born > e.born and o.tokens.len > e.tokens.len and std.mem.eql(u32, o.tokens[0..e.tokens.len], e.tokens)) return true;
        }
        return false;
    }

    /// The entry to free first for `prompt`'s states, never `skip` (a pass's resume). A short prompt (isShort) frees only
    /// short prompts' states, oldest first, else none (its state is refused), so a stream of short prompts never pushes
    /// out a longer prompt's state. A longer prompt frees one a later prompt of its salt extends (never a shared cut nor
    /// a branch point, Entry.branched), oldest first; else the oldest short prompt's; else the oldest.
    fn victimBut(s: *const Store, skip: ?*Entry, prompt: []const u32, salt: u64) ?usize {
        if (s.isShort(prompt.len)) return s.oldestShort(skip);
        var best: ?usize = null;
        for (s.entries.items, 0..) |e, i| {
            if (e.shared or e.branched or e == skip) continue; // shared cuts and branch points go only as the least recently used
            const now = e.salt == salt and prompt.len > e.born and prompt.len > e.tokens.len and std.mem.eql(u32, prompt[0..e.tokens.len], e.tokens); // this prompt extends it
            if ((now or s.extended(e)) and (best == null or e.used < s.entries.items[best.?].used)) best = i;
        }
        if (best) |i| return i;
        if (s.oldestShort(skip)) |i| return i;
        var oldest: ?usize = null;
        for (s.entries.items, 0..) |e, i| if (e != skip and (oldest == null or e.used < s.entries.items[oldest.?].used)) {
            oldest = i;
        };
        return oldest;
    }

    /// Whether freeing every short prompt's state (but `skip`) leaves room for `need` more bytes.
    fn shortRoom(s: *const Store, skip: ?*Entry, need: u64) bool {
        var short: u64 = 0;
        for (s.entries.items) |e| if (e.short and e != skip) {
            short += e.bytes;
        };
        return (s.held -| short) + need <= s.budget;
    }

    fn oldestShort(s: *const Store, skip: ?*Entry) ?usize {
        var short: ?usize = null;
        for (s.entries.items, 0..) |e, i| if (e != skip and e.short and (short == null or e.used < s.entries.items[short.?].used)) {
            short = i;
        };
        return short;
    }
};

/// A line on the engine's log; tests stay quiet (the build runner fails a test that writes to stderr).
fn note(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").is_test) return;
    std.log.warn("prompt cache: " ++ fmt, args);
}

/// The chunk start at or before `at` (0 when none).
fn floorStart(starts: []const u32, at: u32) u32 {
    var best: u32 = 0;
    for (starts) |p| if (p <= at and p > best) {
        best = p;
    };
    return best;
}

test {
    _ = @import("prompt_cache_test.zig");
}
