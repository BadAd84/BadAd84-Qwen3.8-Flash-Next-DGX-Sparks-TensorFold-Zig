//! TF_FLASHNEXT_ROUND_LOG=1: the wall time of a round's backend calls and their parts, each drained, every 64 rounds.
const std = @import("std");
const cuda = @import("cuda");

/// The backend's three calls a round (verify, keep, draft), the parts of verify and draft timed inside them, and a
/// graph window's two halves: the host's staging (the n-gram gather and the uploads it queues) and the graph.
pub const Slot = enum { verify, forward, draws, keep, draft, absorb, pick, chain, stage, graph };
const n_slots = @as(usize, @backingInt(Slot.graph)) + 1;
const every = 64;
/// A wait between two calls longer than this is a request's boundary, not the round loop's host work.
const idle_ms: f64 = 50;

var known = false;
var enabled = false;
var ms: [n_slots]f64 = @splat(0);
var calls: [n_slots]u64 = @splat(0);
var units: [n_slots]u64 = @splat(0);
var between_ms: f64 = 0;
var last_end: f64 = 0;

pub fn on() bool {
    if (!known) {
        known = true;
        if (std.c.getenv("TF_FLASHNEXT_ROUND_LOG")) |v| enabled = std.mem.eql(u8, std.mem.span(v), "1");
    }
    return enabled;
}

fn nowMs(io: std.Io) f64 {
    return @as(f64, @floatFromInt(std.Io.Clock.awake.now(io).toNanoseconds())) / 1e6;
}

fn top(slot: Slot) bool {
    return slot == .verify or slot == .keep or slot == .draft;
}

/// The clock in ms when the log is on (else 0); a backend call also books the host's wait since the last call ended.
pub fn start(io: std.Io, slot: Slot) f64 {
    if (!on()) return 0;
    const t = nowMs(io);
    if (top(slot) and last_end > 0 and t - last_end < idle_ms) between_ms += t - last_end;
    return t;
}

/// `slot` takes the time since `t0` (its start) once the stream has drained; `n` counts its rows or tokens.
pub fn stop(io: std.Io, driver: *const cuda.Driver, stream: cuda.Stream, slot: Slot, t0: f64, n: usize) void {
    if (!on()) return;
    cuda.completion.drain(driver, stream, "flashnext: the round log's drain failed");
    const t = nowMs(io);
    const i = @backingInt(slot);
    ms[i] += t - t0;
    calls[i] += 1;
    units[i] += n;
    if (top(slot)) last_end = t;
    if (slot == .draft and calls[@backingInt(Slot.verify)] >= every) print();
}

/// `slot` takes the host's time since `t0` as it stands: nothing is waited for.
pub fn host(io: std.Io, slot: Slot, t0: f64, n: usize) void {
    if (!on()) return;
    const i = @backingInt(slot);
    ms[i] += nowMs(io) - t0;
    calls[i] += 1;
    units[i] += n;
}

/// The rows of a verify call's windows.
pub fn rows(windows: anytype) usize {
    var n: usize = 0;
    for (windows) |w| n += w.rows();
    return n;
}

/// The rows a keep call's paths keep.
pub fn kept(paths: anytype) usize {
    var n: usize = 0;
    for (paths) |p| n += p.len;
    return n;
}

fn per(slot: Slot, rounds: f64) f64 {
    return ms[@backingInt(slot)] / rounds;
}

fn count(slot: Slot, rounds: f64) f64 {
    return @as(f64, @floatFromInt(units[@backingInt(slot)])) / rounds;
}

fn print() void {
    const rounds: f64 = @floatFromInt(calls[@backingInt(Slot.verify)]);
    std.debug.print("round log: {d:.0} rounds, {d:.2} rows verified and {d:.2} kept a round; ms a round: verify {d:.2} (forward {d:.2}: staging {d:.2}, graph {d:.2}; draws {d:.2}), keep {d:.2}, draft {d:.2} (absorb {d:.2} over {d:.2} rows, picks {d:.2} for {d:.2}, chain {d:.2} for {d:.2} passes), between calls {d:.2}\n", .{
        rounds,                count(.verify, rounds), count(.keep, rounds),
        per(.verify, rounds),  per(.forward, rounds),  per(.stage, rounds),
        per(.graph, rounds),   per(.draws, rounds),    per(.keep, rounds),
        per(.draft, rounds),   per(.absorb, rounds),   count(.absorb, rounds),
        per(.pick, rounds),    count(.pick, rounds),   per(.chain, rounds),
        count(.chain, rounds), between_ms / rounds,
    });
    cuda.kernel_log.dump(rounds);
    ms = @splat(0);
    calls = @splat(0);
    units = @splat(0);
    between_ms = 0;
}
