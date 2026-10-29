# Upstream PR (not posted): patches/0028: the shared expert forked before the router in small decode windows, and its down stored straight into its moe_y slot

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `fea45ba` (main, 2026-10-11); open from me: #34-#36, #42-#50, #53-#57.
Evidence: lane r3-sharedjoin (`~/work/lanes/r3-sharedjoin/`: the nsys node traces and `tl2.py` / `tl3.py`, holds 2, 4 and 5, `h6`, `zabrm-r3sj`; image `r3sj-sj3`), the settle run (`~/work/lanes/b4settle/` `hA.log`, `hB.log`, `sjsum.py`), merged image `zmerge7`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (zmerge7). Clean stack: spark6 `~/work/lanes/b4-pack/` (tf branch `b4` = r1e stack 0001-0024 + 0025-0028, patches `pt/`, image `tensorfold-qwen38:zpr-b4c-stack`, host tests `t.log`, `hostmut4c.out`, GPU `b4q1c.log` / `runs/mut-b4c*.log`, evidence `~/work/gpuev/runs/b4c-*`).
Restyled: work/restyle-b4/shared-expert.final.md (adam-style, reviewed; approved 2026-10-12)

---

**Title:** patches/0028: the shared expert forked before the router in small decode windows, and its down stored straight into its moe_y slot (decode MoE block -3 to -5% in the GPU trace; replies byte-identical)

**Body:**

## Description and Motivation

On one GPU the block-FP8 shared expert of a MoE layer already runs on a side stream beside the routed int4 experts (`TF_FLASHNEXT_SHARED_SIDE`, on by default), but it's forked only after the router, its top-k and the plan, and its down projection writes a scratch buffer that a strided copy then moves into the shared expert's slot of `moe_y`.

An nsys node trace of 1-stream prose decode (about 5,850 MoE blocks, the block from the MLP read-out to `_hc_writeback`, mean 177.7 us) shows the routed int4 down at the DRAM roofline (about 240-250 GB/s) for most of the block. The only stretch with DRAM headroom is the serial prelude (the router, about 15 us at about 170 GB/s, then top-k and the plan, about 5 us), and the shared expert's strided copy is a kernel of its own (about 7 us).

`patches/0028-flash-next-shared-expert-early-fork-slot-store.patch`, two settings:

- `TF_FLASHNEXT_SHARED_EARLY_ROWS=N` (0 to 64; this PR sets 6): a decode window of at most N rows forks its shared expert onto the side stream before the router, so the shared gate|up runs alongside the router, top-k and plan.
  - Prompt passes and larger windows fork after the plan as before: at 8-10 rows the early fork costs up to 11 us a block (the router, on the routed experts' critical path, slows beside the shared gate|up).
  - One GPU only, the int4 experts only.
  - A value above 0 with `TF_FLASHNEXT_SHARED_SIDE=0` stops the start with the setting named, as does a value past 64 or one that isn't a count.
- `TF_FLASHNEXT_SHARED_SLOT_LD=1` (`0` or `1`; any other value stops the start): with a bf16 `moe_y` the shared down stores its rows straight into its slot (the existing `matmulLd` kernels, rows `slots * hidden` apart), so the scratch write and the strided-copy kernel go, at decode and prompt row counts. The MTP head's fp32 `moe_y` keeps the copy.
- Both unset or `0`: the calls the shared expert always made, in the same order (the side-stream block moved into one function unchanged).
- `tensorfold slot-ld-check MODEL` (no weights): random block-FP8 weights at the shared down's shape (n 2,560, K 1,280 and 2,560), in each tile mode (the engine's from the environment, stock, fuse4 with tiles, fuse8), `matmul` plus the strided move against `matmulLd` into a poisoned 6-slot `moe_y` at 27 row counts from 1 to 4,608:
  - every byte of the slot and of the other slots must agree;
  - a mutant (the store one slot early) must differ at every row count.

Why the replies don't change:

- the early fork runs the same kernels on the same inputs into the same slot, only sooner (the side stream still joins before the sum);
- the slot store is the same kernel family writing the same values to the slot's address instead of to a scratch the copy moves there.

Measured by the lane on one DGX Spark, the campaign's build with #34-#36, #42-#50 and #53-#57 (`zmerge6`) vs the same build with the lane's version of this patch, nsys node traces of the decode matrix, the MoE block's mean in us:

| | base | slot store alone | early fork + slot store | change |
| --- | ---: | ---: | ---: | ---: |
| prose, 1 stream | 177.7 | 177.5 | 168.8 | -5.0% |
| prose, 2 streams | 270.3 | 264.5 | 260.4 | -3.7% |
| prose, 4 streams | 395.1 | 392.7 | 392.1 | -0.8% |
| code, 1 stream | 282.4 | | 273.0 | -3.3% |

By window rows at 1 stream:

- 2 rows: 169.8 -> 161.3 us
- 3 rows: 201.1 -> 190.2 us
- 4 rows: 229.9 -> 223.4 us
- 6 rows: 276.4 -> 259.5 us

At 8-10 rows the early fork plus the slot store equals the slot store alone within 2 us, which is why the setting is 6. The same base measured in two holds gave 177.67 and 177.72 us.

Through the recipe's server the gain is inside the noise. Eight interleaved boots of our merged build (`zmerge7`), four with both settings and four without, the median per-request decode tok/s of each boot's matrix:

| | with `0028` (4 boots) | without (4 boots) | change |
| --- | ---: | ---: | ---: |
| code, 1 client | 132.0 (131.6-132.8) | 131.5 (130.5-132.0) | +0.4% |
| code, 2 clients | 91.7 (91.4-92.0) | 91.3 (91.2-91.8) | +0.4% |
| code, 4 clients | 64.2 (63.6-64.5) | 64.6 (63.9-65.0) | -0.7% |
| prose, 1 client | 76.3 (74.7-76.4) | 75.1 (74.3-75.5) | +1.5% |
| prose, 2 clients | 62.1 (61.4-62.5) | 61.4 (59.8-61.8) | +1.1% |
| prose, 4 clients | 40.9 (40.8-41.0) | 40.6 (40.1-40.9) | +0.6% |

Every cell's ranges overlap. I'm sending it for the component gain, which the traces show at every row count it applies to, and because it changes no reply; the serve-level numbers above say it doesn't slow decode.

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
- `slot-ld-check` on GB10 (the engine's own check): PASS on the stack through this batch (an image built from `patches/0001`-`0028`): 216 calls (K 1,280 and 2,560, 4 tile modes, 27 row counts from 1 to 4,608), 0 differ; the slot-early mutant differs at 27 of 27 row counts at both K (killed), exit 0.
- A boot of the recipe's server with this PR's settings (the log reads `shared expert: forked before the router in decode windows of at most 6 rows (0: never); down stored straight into its moe_y slot: true`), golden replies against the stock image's.
  - GPU mutants, each a build of the stack with one line changed, judged by that boot's exit code (the control build, the same stack built the same way, must pass): the slot store one slot early (`slot-ld-wrong-slot`), and the early-fork flag never cleared, so every block after the first fork treats its shared expert as already forked (`early-forked-never-cleared`).
  - The control boot passes (the settings line logged, golden 6/6, exit 0).
  - The slot store one slot early is killed by the golden replies (0 of 6 identical, exit 1).
  - The flag never cleared is killed at load: the start fails with `cuStreamWaitEvent: CUDA_ERROR_INVALID_VALUE` (a block's side stream joined without its fork) and the server exits (exit 2).
- Host tests: `earlyFork` forks decode windows of 1 to N rows only, never a prompt pass, never at 0; the rows setting takes 0 to 64 and refuses a value above 0 without the side stream, past 64, or not a count. Five mutants (the bound exclusive, a prompt pass forked, 0 forking, the side stream ignored, 65 taken), each judged by exit code with the named test among the failures: 5 of 5 killed, each failing `zig build test`; two were first written so that they didn't compile and were rewritten as behaviour changes before they counted.
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
- Memory: unchanged (no allocation; the scratch the slot store skips stays, since the MTP head's fp32 path uses it).
- Not tested:
  - two ranks (the recipe runs one GPU; the early fork never runs on two, the slot store would and wasn't measured there);
  - the settings-off path by a launch-recording host test (the fp8 kernels launch outside the recorder the Triton calls use); it's the original block moved into one function, and the all-settings-off arm above is byte-equal to the stack without this batch.
- The patch is the measured code with the lane's two mutant switches and its extra tile mode (`stages`) in `slot-ld-check` taken out, and the lane's two settings for the early fork (on, and its row limit) made one rows setting.

Other PRs from me: #34-#36, #42-#50 and #53-#57 (`patches/0010`-`0024` and two settings), and in this batch:

- #[0025's PR] (the boot cost table timed again)
- #[0026's PR] (the first token sooner)
- #[0027's PR] (whole-prompt states and `cache_salt`)

`patches/0025`-`0028` are written in that order on top of `0001`-`0024`: each applies with `git apply` after the ones before it. Every prefix of the stack builds and passes `zig build test` and the server and prompt-cache suite `zig/tests/server/zig_test.sh` (which `zig build test` runs on macOS only), each exit 0:

- through `0025`: 207/207 tests and 48 + 17
- through `0026`: 208/208 and 48 + 17
- through `0027`: 210/210 and 49 + 27
- through `0028`: 212/212 and 49 + 27

All of them add CHANGELOG/README/CREDITS lines in the same places, each adds a row to the same new patch table (as #35, #36, #42-#50 and #53-#56 do), and each adds `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase. Main's `## Unreleased` opens with "the image and `patches/` are unchanged"; that line stops being true once any patch PR merges, so I left your wording for the release.

So this PR's patch needs #35, #36, #42-#50, #53-#56, #[0025's PR], #[0026's PR] and #[0027's PR] merged first (logically it needs only #[0026's PR]'s strict 0/1 setting reader).

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [ ] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
