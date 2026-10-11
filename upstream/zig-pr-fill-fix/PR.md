# Upstream PR (not posted): patches/0021: fix TF_FLASHNEXT_FILL=1 with two or more prompts at once

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0); batch 2 open as #42-#50.
Evidence: lane r2d-fill (`~/work/lanes/r2d-fill/`: hold1-3.out, cmp.out, race*.jsonl, repro-server.log; image `r2d-fill1`, mutant image `r2d-fill1m` since removed), host-test mutant `~/work/lanes/r3-prpack/mut0021.sh`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (W7 re-check on zmerge5). Clean stack: spark6 `~/work/lanes/r3-prpack/` (tf = 0001-0024, patches 0021-0024, image `tensorfold-qwen38:zpr3-stack`, host tests `test-stack-fresh.log`).

---

**Title:** patches/0021: fix TF_FLASHNEXT_FILL=1 with two or more prompts at once (prompts fill one after another; a resume's MTP absorb waits for its own chunk)

**Body:**

## Description and Motivation

A correctness fix to the engine's opt-in sliced fill (`TF_FLASHNEXT_FILL=1`: prompts fill in slices of layers
between the other streams' rounds, so a long prompt does not stall the streams that are decoding). It is off by
default in the recipe, so a default install never takes this path; this PR changes no setting. The code it fixes is
the release's own (`patches/0005`: `fillBegin`, `fillStep`, `prefillStepFn`); the speed patches only made it visible.

**The bug.** With `TF_FLASHNEXT_FILL=1`, any two prompts that fill at the same time both fail. On our build every
concurrent request of a 2-client and a 4-client decode matrix came back empty after 0.02-0.04 s, while one client was
fine; the server log says `reason=error (PromptBuffersBusy) prompt=32 tokens=0 after=0.03s`.

- The engine has one set of prompt buffers (`Engine.pfill`), and a prompt chunk stays open over several `fillStep`
  slices (8 layers a step).
- `cuda_lanes.zig` `prefillStepFn` calls `fillStep` for every filling stream on each step. When two prompts fill at
  once (every barrier-started batch of 2+ clients), the second call returns `error.PromptBuffersBusy`, and
  `lanes.Engine.advanceFills` then fails every filling stream.
- One prompt filling beside streams that decode works, which is why a test of one decoder plus one filler passes.

A second, silent defect is on the same path: on a prompt-cache resume, `fillBegin` ran the MTP tail absorb
(`mtp.forward`) in the prompt buffers at once. If another prompt's chunk was open then, the absorb overwrote it and that
other request got a wrong reply, with no error.

**The fix** (`patches/0021-flash-next-sliced-fill-one-at-a-time.patch`):

1. `cuda_lanes.zig` `prefillStepFn`: while another fill holds the prompt buffers, a filling stream skips its slice and
   stays filling. Prompts that arrive together fill one after another, in arrival order.
2. `cuda_engine.zig` `fillBegin` / `fillStep`: on a resume, `fillBegin` parks the snapshot's tail row in the
   sequence's `last_streams` and marks the fill; `fillStep` runs the absorb (`mtp.forward` + `setMtpLen`) when it opens
   this fill's first chunk, after taking the prompt buffers. The order on the sequence is unchanged: restore, absorb,
   chunks. `fillBegin` now touches no prompt buffer.
3. The host tests' `Toy` engine now models the one set of prompt buffers, and a new test starts four streams before
   the first step and checks each against serial decoding.

Measured on one DGX Spark through the recipe's own server, the campaign's build with #34-#36 and #42-#50 (`zmerge5`)
against the same build plus this patch (a lane image), a discarded warm-up boot first, then FILL=0 / FILL=1 and
FILL=1 / FILL=0, golden 6/6 in all 4 arms. Decode matrix (prose and code, 512-token replies, client-side per-request tok/s):

| | prose, 1 / 2 / 4 clients | code, 1 / 2 / 4 clients |
| --- | ---: | ---: |
| `FILL=0`, run a | 72.1 / 59.0 / 39.6 | 125.9 / 88.3 / 63.3 |
| `FILL=0`, run b | 72.5 / 58.2 / 38.1 | 128.4 / 87.2 / 63.3 |
| `FILL=1` with the fix, run a | 72.4 / 60.0 / 39.4 | 127.4 / 88.7 / 64.3 |
| `FILL=1` with the fix, run b | 72.1 / 60.0 / 39.0 | 128.4 / 86.6 / 62.3 |

Every arm: 14/14 replies, none empty, every reply's sha equal to `FILL=0`'s. Speed equal within the spread.

What `FILL=1` buys, and what it costs in time to first token (a 32k prompt sent while another client decodes):

| | the decoding client's longest gap, s | the 32k prompt's time to first token, s |
| --- | ---: | ---: |
| `FILL=0`, run a / b | 11.34 / 11.39 | 11.33 / 11.38 |
| `FILL=1` with the fix, run a / b | 0.22 / 0.25 | 16.06 / 16.70 |

So the setting trades a slower first token for the prompt (sliced fills are also serialised: a burst of two 6-8k
prompts took about 8 s against 2-5 s) for no stall in the decoding streams. Whether it should become the default is a
separate question; this PR only makes it correct.

### The whole stack on RigMark and time to first token, stock against ours

One DGX Spark, the recipe's own server (`start.sh`, the recipe's defaults otherwise), a fresh boot an arm, the golden
replies byte-identical in every arm. Columns: the recipe's last Python release (0.6.1, its published image); this
recipe's Zig release 1.0.0 as published (`tensorfold-qwen38:zig-db28187`); that plus #34-#36 and #42-#50 (the campaign's
merged build `zmerge5`); and that plus this batch (`zmerge6`: the four patches as measured, before the clean-up named
in each PR, with `TF_FLASHNEXT_PREFILL_ROWS=4096`; `TF_FLASHNEXT_FILL` off, so 0021 does not move these numbers). The
last two ran in two sweeps with the arm order reversed (shown as sweep 1 / sweep 2), the first two in their own
sweeps the same day.

Time to first token, client-measured to the first streamed token, median of 3, seconds, thinking off (thinking on is
within ~3% of these rows); cold prompts are new text, the warm turn is +2k tokens on a kept ~100k conversation:

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| cold 1k, idle | 0.707 | 0.464 | 0.426 / 0.432 | 0.503 / 0.406 |
| cold 8k, idle | 3.819 | 2.989 | 2.967 / 2.980 | 2.655 / 2.679 |
| cold 32k, idle | 13.76 | 12.07 | 12.05 / 11.98 | 10.83 / 10.67 |
| cold 120k, idle | 57.20 | 49.62 | 49.62 / 49.54 | 43.24 / 42.50 |
| warm +2k turn, idle | 1.502 | 1.231 | 1.196 / 1.180 | 1.144 / 1.116 |
| cold 1k, 3 streams decoding | 0.922 | 0.537 | 0.494 / 0.511 | 0.468 / 0.474 |
| cold 8k, 3 streams decoding | 4.076 | 3.074 | 3.041 / 3.015 | 2.731 / 2.754 |
| cold 32k, 3 streams decoding | 14.88 | 12.18 | 12.10 / 12.12 | 10.87 / 10.75 |
| cold 120k, 3 streams decoding | 63.87 | 50.01 | 49.86 / 49.82 | 43.16 / 42.88 |
| warm +2k turn, 3 streams decoding | 1.927 | 1.321 | 1.287 / 1.310 | 1.207 / 1.213 |

[RigMark](https://github.com/alexellis/rigmark) (protocol 1.3.0, extra body `{"reasoning_effort": "low"}` as on its
published card for this model; the receipts' medians):

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| code / prose / structured decode, tok/s | 88.0 / 50.5 / 103.3 | 95.4 / 50.1 / 136.6 | 109.7, 110.5 / 57.2, 58.2 / 156.7, 158.2 | 111.2, 112.3 / 58.4, 60.1 / 158.5, 159.1 |
| time to first token, s | 0.28-0.29 | 0.18 | 0.15-0.16 | 0.15-0.17 |
| C1 / C2 / C4 aggregate, tok/s | 68.6 / 94.9 / 129.4 | 59.0 / 97.7 / 150.2 | 70.7, 73.1 / 111.4, 117.9 / 159.4, 168.5 | 72.9, 74.8 / 114.7, 112.5 / 172.9, 171.0 |
| prefill 8K / 32K / 64K cold, tok/s | not run | 2,723 / 2,636 / 2,520 | 2,730, 2,741 / 2,639, 2,642 / 2,546, 2,547 | 3,101, 3,104 / 2,944, 3,032 / 2,876, 2,952 |

Every arm passed RigMark's output gates (code, prose, structured 5/5). RigMark's prefill section needs `/tokenize`,
which the Python server lacks, so the Python arm skipped it (its cold-prompt TTFT rows are the like-for-like prefill
comparison). The stock arms ran under RigMark's published comparison ID, the last two under their own, so their decode
prompts may differ (the #34-#50 build, run in both, gave code 109.8 there and 109.7 / 110.5 here). Against the #34-#50
build, this batch is faster in every cold-prompt cell from 8k up (by 8.6-14.5%) and in the warm turn (4.3-7.4%); two
cells moved the other way in one sweep each: cold 1k idle 0.426 -> 0.503 s in sweep 1 (0.432 -> 0.406 in sweep 2), and
RigMark's C2 aggregate 117.9 -> 112.5 in sweep 2 (111.4 -> 114.7 in sweep 1). The 1k cell was then re-run on its own
(the two builds interleaved, two boots each, 15 prompts a boot): 0.421 / 0.420 s without this batch against 0.401 /
0.404 s with it, thinking off, and 0.449 / 0.452 against 0.423 / 0.430 thinking on; every boot with the batch was faster.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the reference on every boot of every hold quoted here.
- `race.py` (a burst of 4: a 6k extension, a fresh 8k prompt and two short ones, then two fills arriving while a
  client decodes): 8/8 reply shas equal to `FILL=0`, none empty.
- `race2.py` (three rounds of a resumed conversation, a fresh 12k prompt, and a third request 0.6 s later; the server
  log shows 6 resumes at ~6,030-6,090 tokens): 12/12 shas equal to `FILL=0`. Mutant, the fix without its
  `cuda_engine.zig` half (the absorb run at once again): the concurrent fresh prompt's reply is wrong in 2 of 3
  rounds, with no error raised. Killed.
- Host test: the new test passes on the stack; with the skip line removed from `prefillStepFn` it fails (exit
  non-zero), and so does the existing sliced-fill test, which had only passed because the `Toy` had no shared buffers.
- The patch here is the measured code; only its comments are reworded. The whole stack, `patches/0001`-`0024`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 190/190 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (the parked tail row lives in the sequence's existing `last_streams`).

Other PRs from me: #34, #35, #36 and #42-#50 (`patches/0010`-`0020`), and in this batch #[0022's PR] (12-bit read-out weights), #[0023's PR] (indexer select and prompt scores tile), #[0024's PR] (FP8 prompt tiles and int4 prompt gate/up), #[the 4096-row setting's PR] (4096-row prompt chunks). `patches/0021`-`0024` are written in that order on top of `0001`-`0020`: each applies with `git apply` after the ones before it, so this PR's patch needs #35, #36, #42-#50 merged first (for context only: the fix is to code in `0005`, and its `cuda_engine.zig` hunks need `0012`/`0016`'s lines around `fillBegin`). All of them add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35, #36 and #42-#50 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
