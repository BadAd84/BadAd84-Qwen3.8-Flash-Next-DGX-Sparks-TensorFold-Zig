---
name: rework-a-patch-series-into-additive-rungs
description: "A numbered patch stack only builds or behaves as a whole (integration-tail patch, levers never tested alone): rebuild it as per-lever rungs, gate silent reversions, measure each rung against the one before."
---

# Rework a patch series into additive rungs

Use when a numbered patch series on a pinned upstream only compiles at a few prefixes, carries a final
"integration" patch, or was ported blindly and the owner wants each lever proven on its own.
Worked example: Qwen3.8 Flash Next on TensorFold v1.2.6, tooling in
`scripts/qwen38/zig/target/` of `Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig`.

## Order of work (the owner's order, each step's baseline is the step before)
1. Stock, no patches. Repeat it once to learn the noise (here 0.4%).
2. Environment knobs on stock, one per arm, bracketed by baselines. Check what each knob gates before
   trusting a flat arm (e.g. `TF_FLASHNEXT_DRAFTS` only sets SAMPLED chains; a greedy benchmark cannot see it).
   Check whether a "lever" of ours is only a default flip of a knob stock already has: then it belongs here.
3. Our levers one rung at a time, each against the previous accepted rung.

## Building the rungs
- `mkrung.sh K`: pristine tree + old patches 0001..K + `overlay.py K` repairs. Every repair asserts the exact
  text it replaces and lives at the rung where the damage ENTERS, never in a tail patch.
- `mkseries.sh OUT name:cumulative.patch ...`: diffs consecutive rung trees into one patch per lever, then
  replays the series onto a second pristine worktree and compares `git write-tree` ids. Both worktrees must
  be detached at the same base commit or the check lies.
- `mkladder.sh OUT`: all rungs, the series and the gate report in one command.
- `mkpackage.sh` + `mkallow.py`: SHA256SUMS, `apply.sh [--check]` (scratch index, writes nothing), REVERTS.allow.

## Gates before any box build
- Type-check every rung on the laptop: in the tree, `zig build compile-config-server -Dtarget=aarch64-linux-gnu`
  with Zig 0.17.0 via a python subprocess arg list (`work/zigl.py TREE build ...`). ~3.5 min cold, ~10 s to a
  first error. Checks Zig types only, not `.cu` kernels.
- `python scripts/check-patch-reverts.py SERIES [--allow FILE] [--raw]`: reports a line an earlier patch added
  being removed (undo), a removed line coming back (restore), and a base code line deleted with nothing
  resembling it added (delete). Review every finding against the patch context; a real one becomes an
  overlay repair, a refactor gets a reason in the allow file. Prove the gate on the known-bad series first.

## Measuring a rung
- Fresh boot per cell, warm-up arm discarded, baseline repeated at the end, golden vs stock's golden, and the
  boot self-check line (`window self-check: N of 2080`, 1,176 when exact). A rung that faults or reads 0 is
  bisected inside its own group, later levers are re-seated on the last good rung so they still get measured.
- The upstream recipe exports lever settings (`scripts/config.sh`), so a binary that knows a knob runs with
  it ON; an "off" arm passes explicit `=0`. The recipe forwards only `TENSORFOLD_*` and `TF_FLASHNEXT_*` into
  the container: a switch named anything else never reaches the engine and the run silently prints nothing.
- A 512-token prose/code reply cannot show prompt or copy levers: price those with cold-prompt TTFT
  (`prefill_arm.sh`) and the copy/rewrite replies (`copy_arm.sh`).
- Compiles never run beside a timed arm. Queue stages with marker files; `HOLD`/`HOLD2` park the harness so a
  diagnostic can borrow the box between a stage's parts. Never replace a harness script while it is running.
- Restore production at each stage end and confirm `/health` 200.

## When the levers are flat: find where the time is
- Apply `diag/round-and-kernel-logs.patch` on the accepted rung. `TF_FLASHNEXT_ROUND_LOG=1` splits a round into
  verify (staging on host vs graph on GPU), draws, keep and the draft's absorb/picks/chain.
  `TF_FLASHNEXT_KERNEL_LOG=1` with `TF_FLASHNEXT_WINDOW_GRAPH=0` books every launch to its kernel.
- `ckpt_bytes.py MODEL_DIR [LAYER]` reads safetensors headers and sets bytes per part beside the kernel table;
  run it on the target stack's checkpoint too and diff the formats per part.
- State rates per launch (matrix bytes over one launch's time), never checkpoint bytes over ms a round.
