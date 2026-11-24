---
name: benchmark-a-stack-against-a-faster-production-target
description: "Use when measuring whether a rebuilt engine stack (v1.2.x + patches) is slower than a known production serve and by how much: fair-config checks, the silent-container trap, round-economics attribution, and the lever-map diff."
---

# Benchmarking a rebuilt stack against a production target

Use when the question is "is our rebuilt stack slower than production, by how much, and why". Every step below was
learned the hard way on spark6 measuring TensorFold v1.2.6 + 30 patches against the zmerge8 production launch.

## 1. Make the two arms genuinely the same configuration

Read the target document (`speed_target.md` and its "how the cells were measured" block) and match it item by item:
checkpoint, KV dtype, context window, parallelism, thinking mode, warm turns, sampling. Then check the harness source
for hardcoded values that silently override you - `bench_arm.sh` on spark6 hardcoded `CHECKPOINT=nvfp4` while the
target had been measured on a different checkpoint, which invalidates the whole table until parameterised.

A mismatch you cannot remove (the new engine refusing the old checkpoint) is stated in one line, not treated as a
reason to stop measuring: the owner usually wants slower-or-faster and by how much.

## 2. Prove each arm actually booted its own config (the silent-container trap)

A recipe `start.sh` that gates on an image label (`tf.kernels=embedded`) or on the binary accepting an argument will
REFUSE a foreign image and return immediately, leaving the previously running container in place. The arm then
measures that container four times and looks plausible, because its numbers are the old serve's numbers.

Tells: `BOOT seconds 0` or `1`, and a `boot.log` identical across cells with different `--parallel` values.
Verify with two checks per arm: the boot log's parallel/graph line changes with the cell, and `docker inspect` shows a
fresh `Created` stamp. Never accept a cell whose boot time is zero.

For a stack whose binary predates the recipe's arguments, do not fight the recipe: run it through its own launcher,
and make a copy of that launcher with the `exec env` block ending in `${EXTRA:-}` so one lever can be switched off per
arm.

## 3. Decompose the gap before naming a cause

From the decode probe's own counters, compute:

- rounds for a fixed token count (does the stack need more rounds: acceptance/drafter quality?)
- ms per round (is each round dearer: kernels, glue, read-out?)

On Qwen the two arms needed 90 and 81 rounds for 512 code tokens, but 77.7 ms and 49.5 ms a round: a 1.6x
per-round cost, which sends you to the engine's kernels and read-out, not to the drafter's acceptance.

## 4. Do not trust a first cold boot

N-gram tables and weight pages come off disk on the first boot: it reads 3-5% slow. If every "lever off" arm comes
out 3-5% faster than the base, the base was cold and nothing was learned. Interleave, or warm the base and rerun it
last, and treat an identical round count across arms as the signal that those knobs do not change throughput.

## 5. When no knob carries the gap, diff the trees

Knob-set and file-set diffs between the production tree and the rebuilt tree enumerate the port backlog by lever:
`git grep -hoE 'TF_[A-Z0-9_]+' <prod-ref> -- <src>` against the same on the rebuilt tree, then map each
production-only knob to the files that reference it. Production here had 101 knobs to 71 and 93 unique, over a
structurally different engine (109 files against 585), so catching up was a port campaign, not a config change.

## 6. Memory refusals are part of the same question

A stack that refuses N streams at the target window is failing the production requirement. Get the refusal's own
arithmetic (`--parallel 6 needs 30.23 GiB ... leaves 27.27 GiB`), convert to per-stream, and price the components
with the sizing functions (`seqBytesFor`, `streamBytes`, the draft head's `bytes`) rather than guessing. Check whether
a switch you just flipped (drafts on/off) is even read by the estimate: ours priced the draft caches from the loaded
head, so `--no-drafts` changed nothing.

## 7. Restore and record

Every arm run ends by restoring the production serve from its own launcher and confirming `/health`, and every table
is committed with the exact command that produced it. A number nobody can reproduce is not a receipt.
