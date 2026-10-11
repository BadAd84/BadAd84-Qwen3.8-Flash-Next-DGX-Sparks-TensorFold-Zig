//! The n-gram (PLE) table at one GPU is host-mapped (cuda_weights.zig openTable) and gathered on the host a row at
//! a time (NgramTable.gather): a row the page cache does not hold is a synchronous page fault, ~120 us with the
//! kernel's 128 KiB read-around, ~60 us with MADV_RANDOM (random 4 KiB reads on a DGX Spark's NVMe), and a prompt
//! of new text touches 16 cold rows a token. This module keeps the gather's bits (the same rows through the same LUT
//! into the same positions) and changes only when and on which thread the pages are read:
//! - the gang: a gather of at least `min` rows is split into blocks over `threads` worker threads plus the caller's,
//!   so cold rows fault in parallel (the drive does ~200k 4 KiB reads/s at 32 in flight against ~8k serial);
//! - the prefetch queue: row ids whose pages should be resident soon are touched by the same workers in the
//!   background (a prompt's next chunks during prefill, the drafts as the MTP chain produces them in decode);
//! - MADV_RANDOM on the table's mappings (NgramTable.adviseRandom, when `random` is set): a miss reads its page only.
//! Env: TF_FLASHNEXT_NGRAM_THREADS (worker threads; unset or 0: the caller's thread only, the stock path),
//! TF_FLASHNEXT_NGRAM_MIN (rows below which a gather stays on the caller's thread, default 32),
//! TF_FLASHNEXT_NGRAM_PREFETCH (1: the prompt and draft prefetches), TF_FLASHNEXT_NGRAM_RANDOM (1: MADV_RANDOM),
//! TF_FLASHNEXT_NGRAM_AHEAD (prompt chunks queued ahead of the one being staged, default 2, at most `max_ahead`).
const std = @import("std");
const weights = @import("cuda_weights.zig");
const ngram = @import("cuda_ngram.zig");

pub const Options = struct {
    threads: u32 = 0,
    min: usize = 32,
    prefetch: bool = false,
    random: bool = false,
    ahead: usize = 2,

    /// gang threads at most
    pub const max_threads = 128;
    /// prompt chunks queued ahead at most: a prefill queues the rows of (ahead + 1) chunks of up to prefill_rows
    /// tokens (TF_FLASHNEXT_PREFILL_ROWS <= 16,384: at most 17 x 16,384 = 278,528 tokens), so the product cannot
    /// overflow, and a queue never covers more than about one native window
    pub const max_ahead = 16;

    pub fn fromEnv() !Options {
        var o: Options = .{};
        if (std.c.getenv("TF_FLASHNEXT_NGRAM_THREADS")) |v| o.threads = std.fmt.parseInt(u32, std.mem.span(v), 10) catch return bad("TF_FLASHNEXT_NGRAM_THREADS", v);
        if (std.c.getenv("TF_FLASHNEXT_NGRAM_MIN")) |v| o.min = std.fmt.parseInt(usize, std.mem.span(v), 10) catch return bad("TF_FLASHNEXT_NGRAM_MIN", v);
        if (std.c.getenv("TF_FLASHNEXT_NGRAM_PREFETCH")) |v| o.prefetch = !std.mem.eql(u8, std.mem.span(v), "0");
        if (std.c.getenv("TF_FLASHNEXT_NGRAM_RANDOM")) |v| o.random = !std.mem.eql(u8, std.mem.span(v), "0");
        if (std.c.getenv("TF_FLASHNEXT_NGRAM_AHEAD")) |v| o.ahead = std.fmt.parseInt(usize, std.mem.span(v), 10) catch return bad("TF_FLASHNEXT_NGRAM_AHEAD", v);
        if (o.threads > max_threads) return bad("TF_FLASHNEXT_NGRAM_THREADS", std.c.getenv("TF_FLASHNEXT_NGRAM_THREADS").?);
        if (o.ahead > max_ahead) return bad("TF_FLASHNEXT_NGRAM_AHEAD", std.c.getenv("TF_FLASHNEXT_NGRAM_AHEAD").?);
        if (o.prefetch and o.threads == 0) return bad("TF_FLASHNEXT_NGRAM_PREFETCH (needs TF_FLASHNEXT_NGRAM_THREADS > 0)", std.c.getenv("TF_FLASHNEXT_NGRAM_PREFETCH").?);
        return o;
    }

    fn bad(name: []const u8, v: [*:0]const u8) error{BadNgramThreads} {
        std.log.warn("{s}={s} refused: threads 0..{d}, min a row count, ahead 0..{d}", .{ name, std.mem.span(v), max_threads, max_ahead });
        return error.BadNgramThreads;
    }
};

/// The gang and the prefetch queue over one table.
pub const Host = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    table: *const weights.NgramTable,
    g: ngram.NGram,
    o: Options,
    threads: []std.Thread,
    mu: std.Io.Mutex = .init,
    /// workers wait here for a gather block, a touch batch or `quit`
    work: std.Io.Condition = .init,
    /// the gather's caller waits here until every block is done
    done: std.Io.Condition = .init,
    quit: bool = false,
    // the gather in progress (one at a time; the caller works on it too)
    g_ids: []const i64 = &.{},
    g_out: []u16 = &.{},
    g_block: usize = 1,
    g_next: usize = 0, // next block to take
    g_blocks: usize = 0, // blocks in all
    g_left: usize = 0, // blocks not finished
    g_fail: bool = false,
    // row ids whose pages the workers touch in the background, oldest first
    touch: std.ArrayList(i64) = .empty,
    touch_next: usize = 0,
    /// counts, for the log: rows gathered by the gang, rows queued for touching
    gathered: u64 = 0,
    touched: u64 = 0,

    pub fn create(gpa: std.mem.Allocator, io: std.Io, table: *const weights.NgramTable, g: ngram.NGram, o: Options) !*Host {
        const h = try gpa.create(Host);
        errdefer gpa.destroy(h);
        h.* = .{ .gpa = gpa, .io = io, .table = table, .g = g, .o = o, .threads = &.{} };
        const threads = try gpa.alloc(std.Thread, o.threads);
        errdefer gpa.free(threads);
        var n: usize = 0;
        errdefer h.stop(threads[0..n]);
        for (threads) |*t| {
            t.* = try std.Thread.spawn(.{}, worker, .{h});
            n += 1;
        }
        h.threads = threads;
        std.log.info("n-gram table on the host: {d} gather threads (blocks from {d} rows), prefetch {s} ({d} chunks ahead), pages read {s}", .{ o.threads, o.min, if (o.prefetch) "on" else "off", o.ahead, if (o.random) "one at a time (MADV_RANDOM)" else "with the kernel's read-around" });
        return h;
    }

    fn stop(h: *Host, threads: []std.Thread) void {
        h.mu.lockUncancelable(h.io);
        h.quit = true;
        h.work.broadcast(h.io);
        h.mu.unlock(h.io);
        for (threads) |t| t.join();
    }

    pub fn destroy(h: *Host) void {
        h.stop(h.threads);
        h.gpa.free(h.threads);
        h.touch.deinit(h.gpa);
        std.log.info("n-gram host gang: {d} rows gathered in parallel, {d} rows queued ahead", .{ h.gathered, h.touched });
        h.gpa.destroy(h);
    }

    /// Rows `ids` -> `out[ids.len][width]` bf16 bits: NgramTable.gather's bits, blocks of rows over the gang when
    /// there are at least `min` of them.
    pub fn gather(h: *Host, ids: []const i64, out: []u16) !void {
        const t = h.table;
        if (out.len != ids.len * t.width) return error.NgramOutLength;
        if (h.threads.len == 0 or ids.len < h.o.min) return t.gather(ids, out);
        // blocks small enough that cold rows spread over every thread, at least 4 rows each, at most 256
        const want = ids.len / ((h.threads.len + 1) * 4);
        const size = @max(@as(usize, 4), @min(want, 256));
        const blocks = (ids.len + size - 1) / size;
        h.mu.lockUncancelable(h.io);
        h.g_ids = ids;
        h.g_out = out;
        h.g_block = size;
        h.g_next = 0;
        h.g_blocks = blocks;
        h.g_left = blocks;
        h.g_fail = false;
        h.gathered += ids.len;
        h.work.broadcast(h.io);
        // the caller takes blocks too, then waits for the rest
        while (h.g_next < h.g_blocks) {
            const b = h.g_next;
            h.g_next += 1;
            h.mu.unlock(h.io);
            const ok = h.block(b);
            h.mu.lockUncancelable(h.io);
            if (!ok) h.g_fail = true;
            h.g_left -= 1;
        }
        while (h.g_left > 0) h.done.waitUncancelable(h.io, &h.mu);
        const failed = h.g_fail;
        h.g_ids = &.{};
        h.g_out = &.{};
        h.g_blocks = 0;
        h.mu.unlock(h.io);
        if (failed) return error.NgramIdOutOfRange;
    }

    /// Block `b` of the gather in progress (the ids and out slices are read without the lock: they stay until
    /// g_left reaches zero and the caller returns).
    fn block(h: *Host, b: usize) bool {
        const t = h.table;
        const lo = b * h.g_block;
        const hi = @min(lo + h.g_block, h.g_ids.len);
        t.gather(h.g_ids[lo..hi], h.g_out[lo * t.width .. hi * t.width]) catch return false;
        return true;
    }

    /// Row ids whose pages should be resident soon: queued for the workers (nothing waits on them).
    pub fn touchRows(h: *Host, ids: []const i64) void {
        if (!h.o.prefetch or ids.len == 0) return;
        h.mu.lockUncancelable(h.io);
        defer h.mu.unlock(h.io);
        h.touch.appendSlice(h.gpa, ids) catch return;
        h.touched += ids.len;
        h.work.broadcast(h.io);
    }

    /// The rows of `tokens` after `history` (the n - 1 tokens before them), queued for touching.
    pub fn touchTokens(h: *Host, history: []const i64, tokens: []const i64) void {
        if (!h.o.prefetch or tokens.len == 0) return;
        var stack: [64 * ngram.max_heads]i64 = undefined;
        const n = tokens.len * h.g.heads;
        const buf = if (n <= stack.len) stack[0..n] else h.gpa.alloc(i64, n) catch return;
        defer if (n > stack.len) h.gpa.free(buf);
        h.g.ids(history, tokens, buf) catch return;
        h.touchRows(buf);
    }

    /// The newest draft's rows queued for touching: `drafts` follow `first` (the next window's pending token), which
    /// follows the stream's committed `history`; the newest draft's n - 1 predecessors come from there.
    pub fn touchDraft(h: *Host, history: []const i64, first: u32, drafts: []const u32) void {
        if (!h.o.prefetch or drafts.len == 0) return;
        const c = h.g.n - 1;
        var hist: [ngram.max_n]i64 = undefined;
        draftHistory(history[0..c], first, drafts, hist[0..c]);
        h.touchTokens(hist[0..c], &.{@as(i64, @intCast(drafts[drafts.len - 1]))});
    }

    /// Prompt tokens [from, to) of `prompt` queued for touching, each token's rows after its own predecessors
    /// (the prompt's start has the EOS history, as stage's ids give it; a resumed prompt's chunks keep their
    /// predecessors too).
    pub fn touchPrompt(h: *Host, prompt: []const u32, from: usize, to: usize) void {
        if (!h.o.prefetch or from >= to) return;
        const c = h.g.n - 1;
        var hist: [ngram.max_n]i64 = undefined;
        var toks: [1024]i64 = undefined;
        var at = from;
        while (at < to) {
            const end = @min(to, at + toks.len);
            for (0..c) |i| hist[i] = if (at + i >= c) @as(i64, @intCast(prompt[at + i - c])) else h.g.eos;
            for (toks[0 .. end - at], prompt[at..end]) |*d, s| d.* = @intCast(s);
            h.touchTokens(hist[0..c], toks[0 .. end - at]);
            at = end;
        }
    }

    /// Everything queued but not yet touched is dropped (a prompt that stopped early).
    pub fn dropTouches(h: *Host) void {
        h.mu.lockUncancelable(h.io);
        defer h.mu.unlock(h.io);
        h.touch.clearRetainingCapacity();
        h.touch_next = 0;
    }

    fn worker(h: *Host) void {
        var batch: [32]i64 = undefined;
        h.mu.lockUncancelable(h.io);
        while (true) {
            if (h.quit) break;
            if (h.g_next < h.g_blocks) {
                const b = h.g_next;
                h.g_next += 1;
                h.mu.unlock(h.io);
                const ok = h.block(b);
                h.mu.lockUncancelable(h.io);
                if (!ok) h.g_fail = true;
                h.g_left -= 1;
                if (h.g_left == 0) h.done.signal(h.io);
                continue;
            }
            if (h.touch_next < h.touch.items.len) {
                const n = @min(batch.len, h.touch.items.len - h.touch_next);
                @memcpy(batch[0..n], h.touch.items[h.touch_next..][0..n]);
                h.touch_next += n;
                if (h.touch_next == h.touch.items.len) {
                    h.touch.clearRetainingCapacity();
                    h.touch_next = 0;
                }
                h.mu.unlock(h.io);
                h.table.touch(batch[0..n]);
                h.mu.lockUncancelable(h.io);
                continue;
            }
            h.work.waitUncancelable(h.io, &h.mu);
        }
        h.mu.unlock(h.io);
    }
};

/// The `out.len` tokens before the newest of `drafts` in the sequence history ++ [first] ++ drafts (history holds
/// at least out.len tokens, the stream's committed n - 1).
fn draftHistory(history: []const i64, first: u32, drafts: []const u32, out: []i64) void {
    const newest: isize = @intCast(drafts.len); // its position in [first, drafts...]
    for (out, 0..) |*o, i| {
        const pos = newest - @as(isize, @intCast(out.len - i));
        o.* = if (pos >= 1) @intCast(drafts[@intCast(pos - 1)]) else if (pos == 0) @intCast(first) else history[@intCast(@as(isize, @intCast(history.len)) + pos)];
    }
}

test "a draft's predecessors give the ids stage computes for the next window" {
    const g = try ngram.NGram.init(.{ .vocab = 248320, .ngram_size = 3, .heads_per_ngram = 8, .vocab_base = 20000000, .divisor = 128, .seed = 1234, .eos = 248044, .embed_dim = 2560 });
    const history = [_]i64{ 123, 456 };
    const first: u32 = 789;
    const drafts = [_]u32{ 11, 248044, 7, 8 };
    // the next window as stage sees it: first, then the drafts, after the history
    const window = [_]i64{ 789, 11, 248044, 7, 8 };
    var want: [window.len * 16]i64 = undefined;
    try g.ids(&history, &window, &want);
    for (1..drafts.len + 1) |n| {
        var hist: [2]i64 = undefined;
        draftHistory(&history, first, drafts[0..n], &hist);
        var got: [16]i64 = undefined;
        try g.ids(&hist, &.{@as(i64, @intCast(drafts[n - 1]))}, &got);
        try std.testing.expectEqualSlices(i64, want[n * 16 ..][0..16], &got);
    }
}

test "a chunk's touch ids from its own history equal the whole prompt's at those positions" {
    const g = try ngram.NGram.init(.{ .vocab = 248320, .ngram_size = 3, .heads_per_ngram = 8, .vocab_base = 20000000, .divisor = 128, .seed = 1234, .eos = 248044, .embed_dim = 2560 });
    const toks = [_]i64{ 9707, 11, 1879, 248044, 314, 2001, 248319, 0, 248044, 248044, 77, 5, 6, 7 };
    var h: [2]i64 = undefined;
    g.initialHistory(&h);
    var all: [toks.len * 16]i64 = undefined;
    try g.ids(&h, &toks, &all);
    const from = 5;
    var part: [(toks.len - from) * 16]i64 = undefined;
    try g.ids(toks[from - 2 .. from], toks[from..], &part);
    try std.testing.expectEqualSlices(i64, all[from * 16 ..], &part);
}

test "the gang's gather is the serial gather byte for byte, errors included" {
    const gpa = std.testing.allocator;
    const io = std.testing.io;
    const g = try ngram.NGram.init(.{ .vocab = 248320, .ngram_size = 3, .heads_per_ngram = 8, .vocab_base = 20000000, .divisor = 128, .seed = 1234, .eos = 248044, .embed_dim = 2560 });
    // three shards of random fp8 codes, the last shorter, as the table's own layout
    const width: u32 = 160;
    const shard_rows = [_]u64{ 100, 100, 37 };
    var t: weights.NgramTable = .{ .gpa = gpa, .io = io, .width = width, .fp8 = true };
    defer {
        for (t.shards.items) |s| gpa.free(s);
        t.shards.deinit(gpa);
        t.starts.deinit(gpa);
    }
    var prng = std.Random.DefaultPrng.init(7);
    const rnd = prng.random();
    try t.starts.append(gpa, 0);
    for (shard_rows) |n| {
        const bytes = try gpa.alloc(u8, n * width);
        rnd.bytes(bytes);
        try t.shards.append(gpa, bytes);
        try t.starts.append(gpa, t.starts.items[t.starts.items.len - 1] + n);
    }
    t.rows = t.starts.items[t.starts.items.len - 1];
    for (&t.lut, 0..) |*v, i| v.* = @intCast((i * 2654435761) & 0xFFFF);
    const h = try Host.create(gpa, io, &t, g, .{ .threads = 5, .min = 32, .prefetch = true });
    defer h.destroy();
    // sizes below and above the threshold, ids over every shard and both boundaries, repeats included
    for ([_]usize{ 1, 31, 32, 33, 200, 1000, 4097 }) |n| {
        const ids = try gpa.alloc(i64, n);
        defer gpa.free(ids);
        for (ids, 0..) |*id, i| id.* = if (i % 7 == 0) 199 else if (i % 11 == 0) 100 else @intCast(rnd.uintLessThan(u64, t.rows));
        const want = try gpa.alloc(u16, n * width);
        defer gpa.free(want);
        const got = try gpa.alloc(u16, n * width);
        defer gpa.free(got);
        try t.gather(ids, want);
        @memset(got, 0xAAAA);
        try h.gather(ids, got);
        try std.testing.expectEqualSlices(u16, want, got);
        h.touchRows(ids); // the prefetch path over the same ids (a mutant that skips the touch is not what this tests)
    }
    // an id past the table fails the gang as it fails the serial gather
    const bad = try gpa.alloc(i64, 64);
    defer gpa.free(bad);
    @memset(bad, 3);
    bad[50] = @intCast(t.rows);
    const out = try gpa.alloc(u16, 64 * width);
    defer gpa.free(out);
    try std.testing.expectError(error.NgramIdOutOfRange, t.gather(bad, out));
    try std.testing.expectError(error.NgramIdOutOfRange, h.gather(bad, out));
    try std.testing.expectError(error.NgramOutLength, h.gather(bad, out[0..10]));
}

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern "c" fn unsetenv(name: [*:0]const u8) c_int;

test "the settings are refused past their caps, so (ahead + 1) x the prompt rows cannot overflow" {
    defer for ([_][*:0]const u8{ "TF_FLASHNEXT_NGRAM_THREADS", "TF_FLASHNEXT_NGRAM_AHEAD", "TF_FLASHNEXT_NGRAM_PREFETCH" }) |n| {
        _ = unsetenv(n);
    };
    _ = setenv("TF_FLASHNEXT_NGRAM_THREADS", "32", 1);
    _ = setenv("TF_FLASHNEXT_NGRAM_PREFETCH", "1", 1);
    _ = setenv("TF_FLASHNEXT_NGRAM_AHEAD", "16", 1);
    try std.testing.expectEqual(@as(usize, 16), (try Options.fromEnv()).ahead);
    for ([_][*:0]const u8{ "17", "18446744073709551615", "-1", "two" }) |v| {
        _ = setenv("TF_FLASHNEXT_NGRAM_AHEAD", v, 1);
        try std.testing.expectError(error.BadNgramThreads, Options.fromEnv());
    }
    _ = setenv("TF_FLASHNEXT_NGRAM_AHEAD", "2", 1);
    _ = setenv("TF_FLASHNEXT_NGRAM_THREADS", "129", 1);
    try std.testing.expectError(error.BadNgramThreads, Options.fromEnv());
    _ = setenv("TF_FLASHNEXT_NGRAM_THREADS", "0", 1);
    try std.testing.expectError(error.BadNgramThreads, Options.fromEnv()); // the prefetch runs on the workers
    // the largest product the engine can form: (max_ahead + 1) chunks of the most prompt rows it accepts
    try std.testing.expect((Options.max_ahead + 1) * 16384 < std.math.maxInt(u32));
}
