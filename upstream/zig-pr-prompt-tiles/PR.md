# Upstream PR (not posted): patches/0024: larger block-FP8 prompt tiles and the int4 prompt kernel for the experts' gate/up

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0); batch 2 open as #42-#50.
Evidence: lane r2c-fable (`~/work/lanes/r2c-fable/`: out1 (tiles-check), out2, out2b, out-gu, out-fin; images `r2c-fable-t3`, `r2c-fable-t4`), merged image `zmerge6` (`~/work/bench/zrm6.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (Round 2, R2C). Clean stack: spark6 `~/work/lanes/r3-prpack/` (tf = 0001-0024, patches 0021-0024, image `tensorfold-qwen38:zpr3-stack`, host tests `test-stack-fresh.log`).

---

**Title:** patches/0024: larger block-FP8 prompt tiles and the int4 prompt kernel for the experts' gate/up (cold prefill +5.3 to +5.5% at 8k-128k, replies byte-identical)

**Body:**

## Description and Motivation

A 2,048-row prompt chunk of real text spends about a third of its time in the routed experts (gate/up 153.5 ms,
down 95.1 ms of ~780 ms) and much of the rest in the block-FP8 projections. Both run tiles sized for decode-sized calls.

`patches/0024-flash-next-prompt-fp8-tiles-int4-gate-up.patch`, prompt chunks only:

- `TF_FLASHNEXT_FP8_PROMPT_TILES=1`: from 256 rows, one-slice block-FP8 shapes of 8,192+ columns (the DeltaNet qkvz
  16384 x 2560 and attention qkv 13312 x 2560 projections) run `qmmf_kernel` on a 128 x 128 tile (2 x 4 warps, 3
  stages; a block reads two 64-column tiles of words and scales) instead of 64 x 64 in 4 stages, and split-K shapes of
  2,048+ columns (out_proj 2560 x 6144, the shared expert's gate/up and down) run the fused prompt form in 2 stages
  instead of 4 (half the shared memory a block, so 3 blocks a multiprocessor instead of 2). Narrower shapes keep the
  4-stage form: the MTP layer's hyper-connection down (324 columns over K 10,240, 192 blocks) lost 18% on 2 stages.
- `TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1`: a prompt call's routed gate/up runs on `int4_prompt_kernel` (until now only the
  prompt down did) with both matrices and the SwiGLU epilogue, on items of up to 64 pairs: an expert's words are read
  once an item instead of once every 16 pairs. 2 x 4 warps, 2 x 4 tiles a warp (64 rows x 128 columns a block), 3
  stages.
- `tensorfold fp8-tiles-check MODEL` (no weights): every tile mode against the stock kernel at prompt row counts, bytes
  compared, with two mutants, then timed. `int4-check` also compares the prompt gate/up with `int4_kernel`. The boot
  log names both settings.

Why the replies do not change: a row's bits depend only on the K order and the per-output MMA and scale sequence, which
the tiles keep; the gate/up kernel does `int4_kernel`'s arithmetic per output.

Kernel time in the engine (2,048 rows, median of 5): qkvz 2,800 -> 2,463 us, attention qkv 2,332 -> 2,004, out_proj
1,256 -> 1,098, the shared expert's gate/up 496 -> 420 and down 278 -> 238 (+12-15% at 4,096 rows); the experts'
gate/up in an eager profile 151.0 / 150.4 -> 131.7 ms a chunk (code / prose text, -12.8%).

Measured on one DGX Spark through the recipe's own server: the campaign's build with #34-#36 and #42-#50 (`zmerge5`)
against the same build plus both changes (a lane image), a warm-up boot then base / both / both / base, golden 6/6 on
all 5 boots; cold prompts of new text, time to first token as prompt tokens a second, every run listed:

| | base | with `0024` | change of the median |
| --- | --- | --- | ---: |
| 8k | 2,915 2,930 2,932 2,883 2,917 2,913 | 3,077 3,100 3,052 3,060 3,075 3,080 | +5.5% |
| 32k | 2,861 2,853 2,837 2,844 2,825 2,823 | 3,015 3,000 2,995 3,006 2,987 2,988 | +5.5% |
| 128k | 2,564 2,510 2,568 2,564 | 2,698 2,700 2,699 2,696 | +5.3% |

Every run with the patch is above every base run. Each change alone, in earlier holds: the tiles +1.9% and +2.7% at
128k (every tiles run above every base run in both holds), +2-5% at 8k and 32k; the gate/up on top of the tiles
+2.1 / +1.6 / +3.2% at 8k / 32k / 128k (every run above at 128k).

Measured and left out: the 64 x 64 tile in 2 stages for the wide shapes (the tile sweep picked 128 x 128), three other gate/up
shapes (2 stages; 4 x 2 warps in 4 stages; 4 x 2 warps with 1 x 2 tiles), and an `int4_prompt_kernel` variant that
keeps its copy ring full across items (the same bytes, but the down 12% slower).

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

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the reference on every boot of every hold quoted here. (15 boots over three holds.)
- `fp8-tiles-check` on GB10: PASS on six prompt shapes (the five above and the MTP layer's narrow hc down) at rows
  255, 256, 300, 1,024, 2,048 and 2,049, bf16, fp32 and the strided form, random e4m3 codes and scales, the output
  poisoned before every call: 0 of 72 / 48 calls a shape differ from the stock kernel. Two mutants, the fused form told
  half the slices and the wide tile told a K of 64 less, differ on every call they run (15/15, 10/10). That run used
  the lane's first build, before the narrow-shape gate; in this patch the check runs the mutants only where the new
  kernels run, so the gated shape no longer counts a mutant it cannot see.
- `int4-check` on GB10: the prompt gate/up's bf16 SwiGLU bytes equal `int4_kernel`'s on every pair, the skipped shared
  slot left untouched. The engine bench's reply shas are identical with and without the tiles (code `f5f86b2cefc1`,
  prose `0d5b96e12e42`).
- The patch here is the measured code with the shapes left out above taken out (one gate/up shape, the 128 x 128 tile only), one switch for each change in place of the lane's per-shape switches, and a per-layer expert-count diagnostic dropped. The whole stack, `patches/0001`-`0024`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 190/190 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (the tiles and the gate/up use shared memory and the same plan buffers).

Other PRs from me: #34, #35, #36 and #42-#50 (`patches/0010`-`0020`), and in this batch #[0021's PR] (the sliced-fill fix), #[0022's PR] (12-bit read-out weights), #[0023's PR] (indexer select and prompt scores tile), #[the 4096-row setting's PR] (4096-row prompt chunks). `patches/0021`-`0024` are written in that order on top of `0001`-`0020`: each applies with `git apply` after the ones before it, so this PR's patch needs #35, #36, #42-#50, #[0021's PR], #[0022's PR], #[0023's PR] merged first (logically it needs only #48's fused prompt form and fp8-fused-check). All of them add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35, #36 and #42-#50 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
