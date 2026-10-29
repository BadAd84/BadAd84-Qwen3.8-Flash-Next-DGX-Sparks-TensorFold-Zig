# Upstream PR (not posted): patches/0026: a prompt's first token sooner, drawn before the last chunk's MTP absorb, with the unused MTP head of a one-prompt pass skipped and the host n-gram gather beside the first layers

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `fea45ba` (main, 2026-10-11); open from me: #34-#36, #42-#50, #53-#57.
Evidence: lane r3-ttft1k (`~/work/lanes/r3-ttft1k/`: the TTFT profile, the interleaved holds, `zabrm-r3t`; image `r3t-b`), merged image `zmerge7`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (zmerge7). Clean stack: spark6 `~/work/lanes/b4-pack/` (tf branch `b4` = r1e stack 0001-0024 + 0025-0028, patches `pt/`, image `tensorfold-qwen38:zpr-b4c-stack`, host tests `t.log`, `hostmut4c.out`, GPU `b4q1c.log` / `runs/mut-b4c*.log`, evidence `~/work/gpuev/runs/b4c-*`).
Restyled: work/restyle-b4/first-token.final.md (adam-style, reviewed; approved 2026-10-12)

---

**Title:** patches/0026: a prompt's first token sooner, drawn before the last chunk's MTP absorb, with the unused MTP head of a one-prompt pass skipped and the host n-gram gather beside the first layers (cold 1k-3k TTFT -3 to -4%; replies byte-identical)

**Body:**

## Description and Motivation

A short prompt's time to first token is mostly GPU time (about 392 ms of a cold 1k prompt), but three pieces of work sit in front of the first token that it doesn't need:

- the last chunk's MTP absorb and commit (about 12 ms at 1k) run before the first token is drawn, although the draw only reads the logits row the chunk has already produced;
- a one-prompt pass runs the MTP head to its logits, and every caller throws those logits away (a pass of several prompts already stops after the head's layer);
- the host n-gram gather (10-15 ms at 1k) runs before the chunk's embedding is launched, so the GPU just waits for it.

`patches/0026-flash-next-first-token-sooner.patch`, three settings (each `0` or `1`; unset or `0` runs the original code path; any other value stops the start with the setting named):

- `TF_FLASHNEXT_EARLY_DRAW=1`: the first token is drawn as soon as the last chunk's logits row is copied out, before that chunk's MTP absorb and commit, for one prompt and for a burst of prompts in one pass. Same draw on the same row; the host has the token while those kernels are still to come.
- `TF_FLASHNEXT_PROMPT_HEAD_SKIP=1`: a one-prompt pass's MTP head stops after its layer (its cache written), as a burst's always did, unless a dump records the head. It's part of the settings text both ranks have to agree on.
- `TF_FLASHNEXT_NGRAM_LATE=1`: a prompt pass's host-gathered n-gram rows are gathered and uploaded once the embedding and the layers before the first n-gram layer are launched (just before that layer's n-gram block reads them), so the gather's page faults run alongside GPU work.
  - Only with the table on the host; the device table is unchanged.
  - A pass that ends or fails leaves nothing pending, and a deferred gather that was never staged is an error, not a silent skip.
- `tensorfold first-token-check MODEL`: each setting on, and all three, against all three off on the real engine:
  - prompts of 7 to 9,000 tokens, greedy and sampled (the recipe's sampling, seed 1234);
  - a prompt resumed from a state kept at its half;
  - a burst of three prompts in one pass.

  Every run's first token, drafted reply, rounds, drafts and accepted drafts must match the reference's (the drafts read the MTP head's cache, so a head that skipped writing it shows).

Measured on one DGX Spark through the recipe's server, the campaign's build with #34-#36, #42-#50 and #53-#57 (`zmerge6`) vs the same build plus the lane's version of this patch, interleaved (base, ours, ours, base; 12 prompts a boot), median TTFT in seconds, golden 6/6 on every boot:

| | base | with `0026` | change |
| --- | --- | --- | ---: |
| cold 1k, thinking off | 0.398 / 0.402 | 0.387 / 0.380 | -3.8% |
| cold 1k, thinking on | 0.424 / 0.426 | 0.409 / 0.404 | -4.1% |
| cold 3k, thinking off | 1.003 / 0.996 | 0.974 / 0.948 | -3.6% |
| cold 3k, thinking on | 1.020 / 1.026 | 0.996 / 0.980 | -3.2% |

Every boot with the patch was faster than every boot without it. With all three settings off the same image measured 1k 0.396 s and 3k 0.992 s (the base's numbers).

On the clean stack built from these patches, cold ~1k prompts, the whole stack through this batch vs the stack before it, 12 samples each on fresh boots, golden 6/6 on both:

- thinking off: 0.387 -> 0.376 s idle (-2.7%) and 0.450 -> 0.444 s with 3 streams decoding (-1.2%)
- thinking on: 0.414 -> 0.402 s (-3.1%) and 0.471 -> 0.462 s (-2.1%)

### The whole stack on RigMark and time to first token, stock against ours

One DGX Spark, the recipe's own server (`start.sh`, the recipe's defaults otherwise), a fresh boot per arm, golden replies byte-identical in every arm. Columns:

- the recipe's last Python release (0.6.1, its published image);
- this recipe's Zig release 1.0.0 as published (`tensorfold-qwen38:zig-db28187`);
- that plus #34-#36, #42-#50 and #53-#57 as they stand after review round 1 (an image built from exactly `patches/0001`-`0024`);
- and that plus this batch (an image built from exactly `patches/0001`-`0028`, with this batch's `scripts/config.sh` settings).

The last two ran in one sweep (comparison ID `zrm-b4c`, 2026-10-11, golden 6/6 in both arms), the first two in their own sweeps on 2026-10-10.

Time to first token, client-measured to the first streamed token, median of 3, in seconds, thinking off. Cold prompts are new text; the warm turn is +2k tokens on a kept ~100k conversation:

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50, #53-#57 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| cold 1k, idle | 0.707 | 0.464 | 0.402 | 0.388 |
| cold 8k, idle | 3.819 | 2.989 | 2.616 | 2.604 |
| cold 32k, idle | 13.76 | 12.07 | 10.56 | 10.46 |
| cold 120k, idle | 57.20 | 49.62 | 42.15 | 42.02 |
| warm +2k turn, idle | 1.502 | 1.231 | 1.095 | 1.074 |
| cold 1k, 3 streams decoding | 0.922 | 0.537 | 0.466 | 0.463 |
| cold 8k, 3 streams decoding | 4.076 | 3.074 | 2.666 | 2.664 |
| cold 32k, 3 streams decoding | 14.88 | 12.18 | 10.69 | 10.61 |
| cold 120k, 3 streams decoding | 63.87 | 50.01 | 42.60 | 42.25 |
| warm +2k turn, 3 streams decoding | 1.927 | 1.321 | 1.180 | 1.156 |

[RigMark](https://github.com/alexellis/rigmark) (protocol 1.3.0, extra body `{"reasoning_effort": "low"}` like on its published card for this model; the receipts' medians):

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50, #53-#57 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| code / prose / structured decode, tok/s | 88.0 / 50.5 / 103.3 | 95.4 / 50.1 / 136.6 | 113.6 / 61.5 / 159.6 | 114.4 / 63.7 / 162.2 |
| time to first token, s | 0.28-0.29 | 0.18 | 0.15-0.16 | 0.14-0.15 |
| C1 / C2 / C4 aggregate, tok/s | 68.6 / 94.9 / 129.4 | 59.0 / 97.7 / 150.2 | 74.1 / 114.6 / 175.4 | 75.7 / 117.4 / 178.0 |
| prefill 8K / 32K / 64K cold, tok/s | not run | 2,723 / 2,636 / 2,520 | 3,115 / 3,055 / 2,975 | 3,239 / 3,103 / 3,015 |
| prefill 8K / 32K / 64K immediate replay, tok/s | not run | 2,725 / 2,639 / 2,496 | 3,157 / 3,061 / 2,977 | 1,854,233 / 1,321,877 / 1,332,656 (the whole-prompt state: no forward) |

The two stock arms passed RigMark's output gates 5/5 in code, prose and structured. The last two, in one sweep under their own comparison ID (so their decode prompts differ from the stock arms'), both passed code and structured 5/5 and prose 3/5: the same two prose prompts hit the 8,192-token reply cap in both (every prose reply the same length in both arms), so RigMark's cards for that sweep say not to headline them. I quote them for the comparison between the two.

RigMark's prefill section needs `/tokenize`, which the Python server lacks, so the Python arm skipped it.

One cell of the sweep went the wrong way: cold 1k with thinking on while 3 streams decode (0.466 -> 0.473 s, +1.5%, 3 samples; not in the table, which shows thinking off). A re-run of the cold 1k cells, 12 samples each, on fresh boots of both images (`zrm-b4c1k`, golden 6/6 both) settled it:

- thinking on, 3 streams decoding: 0.471 -> 0.462 s (-2.1%)
- thinking off, idle: 0.387 -> 0.376 (-2.7%)
- thinking on, idle: 0.414 -> 0.402 (-3.1%)
- thinking off, 3 streams decoding: 0.450 -> 0.444 (-1.2%)

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image's on every boot of every hold quoted here.
- `first-token-check` on GB10 (the engine's own check, serve stopped, the recipe's settings): PASS on the stack through this batch (an image built from `patches/0001`-`0028`): 5 modes x 16 runs, the 64 runs with a setting on compared with every setting off (first token, 64-token drafted reply, rounds, drafts and accepted drafts), 0 differ, exit 0.
  - The prompts are plain text with no chat header, and the check fails unless the reference's first tokens differ across the lengths (with one header every prompt drew the same end-of-turn token, which hid a draw from a stale row; that run is why the guard is there).
  - GPU mutants, each a build of the stack with one line moved, judged by the check's exit code (the control build, the same stack built the same way, must pass): the early draw taken before the logits row is copied out (`early-draw-before-logits-copy`), the head's stop placed before its layer so the head writes no cache (`head-skip-before-layer`), and the deferred n-gram rows uploaded after the first n-gram block has read them (`ngram-late-after-ple`).
  - The control passes (exit 0) and all three are killed by exit code: the early draw before the copy differs in 18 of 64 runs (its first token, e.g. 4099 against 1067 at 5,200 tokens sampled), the head stopped before its layer in 16 (the same first token, then other rounds and drafts), the late n-gram rows in 30.
- Host test: the three settings take `0` or `1` only; `""`, `on`, `off`, `2`, `01`, `1 `, `true` and `-1` are refused, never read as either. Its mutant (any other value read as on) fails it: killed (`zig build test` exit 1, the named test among the failures).
- Four greedy prompts at once, three rounds: replies identical with the patch, with all three settings off, and without the patch; draft counters after the golden replies identical everywhere (575 drafted, 429 accepted).
- The recipe's own tools on one GB10, each arm the recipe's `start.sh` at its defaults (8 x 262,144, fp8 KV, vision on): stock 1.0.0 (`tensorfold-qwen38:zig-db28187`, recipe main) and the whole stack through this batch (an image built from exactly `patches/0001`-`0028`, the recipe tree with every open PR of mine laid over main), in the same session. Stock / stack:
  - golden 6/6 both;
  - `tools/exact.py` PASS / PASS (482 / 527 drafts accepted; drafted equal to `"draft": false`, concurrent equal to one at a time);
  - `tools/exact.py --pad 3k` PASS / PASS (498 / 522);
  - `tools/toolcheck.py` 3/3 / 3/3;
  - `tools/needle.py` found / found at 199,730 tokens (prefill 89.33 / 73.16 s).

  The recipe has no `bench_draft` or `exact_prefill` file, so their forms ran as probes:
  - recipe sampling (temperature 1.0, top_p 0.95, top_k 20) with seed 1234, drafted, `"draft": false` and all at once: 38/38 replies identical to stock, drafted == `"draft": false` == concurrent for 11/11 prompts (1,479 drafts accepted);
  - cold greedy prompts of about 8k, 32k and 120k tokens, the 32k one again with `"draft": false`: 5/5 replies identical to stock;
  - 14 replies of four prompts arriving while others fill, identical to the stack without this batch.
- Every batch-4 setting off on the same image (`TF_FLASHNEXT_COST_RETIME=0`, `TF_FLASHNEXT_EARLY_DRAW=0`, `TF_FLASHNEXT_PROMPT_HEAD_SKIP=0`, `TF_FLASHNEXT_NGRAM_LATE=0`, `TENSORFOLD_PROMPT_CACHE_WHOLE=0`, `TF_FLASHNEXT_SHARED_EARLY_ROWS=0`, `TF_FLASHNEXT_SHARED_SLOT_LD=0`): golden 6/6; `exact.py` PASS (527 drafts accepted); 38/38 sampled and 5/5 prefill replies identical to stock and to the stack without this batch (an image of `patches/0001`-`0024` at its defaults, the same probes); prompts of 1,100-65,536 tokens sent again and extended by 64 tokens keep nothing and match their cold replies.
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (no allocation; the draw and the gather just move, and the skipped head work frees nothing it held).
- The patch is the measured code with the lane's mutant switch and its head knob (on by default there) taken out; the head skip is now a setting that's off unless set, like the other two.

Other PRs from me: #34-#36, #42-#50 and #53-#57 (`patches/0010`-`0024` and two settings), and in this batch:

- #[0025's PR] (the boot cost table timed again)
- #[0027's PR] (whole-prompt states and `cache_salt`)
- #[0028's PR] (the shared expert forked early and stored into its slot)

`patches/0025`-`0028` are written in that order on top of `0001`-`0024`: each applies with `git apply` after the ones before it. Every prefix of the stack builds and passes `zig build test` and the server and prompt-cache suite `zig/tests/server/zig_test.sh` (which `zig build test` runs on macOS only), each exit 0:

- through `0025`: 207/207 tests and 48 + 17
- through `0026`: 208/208 and 48 + 17
- through `0027`: 210/210 and 49 + 27
- through `0028`: 212/212 and 49 + 27

All of them add CHANGELOG/README/CREDITS lines in the same places, each adds a row to the same new patch table (as #35, #36, #42-#50 and #53-#56 do), and each adds `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase. Main's `## Unreleased` opens with "the image and `patches/` are unchanged"; that line stops being true once any patch PR merges, so I left your wording for the release.

So this PR's patch needs #35, #36, #42-#50, #53-#56 and #[0025's PR] merged first (logically it needs only #42's host n-gram gather, which `TF_FLASHNEXT_NGRAM_LATE` defers).

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [ ] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
