# Upstream PR (not posted): patches/0022: decode read-outs from a lossless 12-bit copy of their weights

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0); batch 2 open as #42-#50.
Evidence: lane r2b-opus (`~/work/lanes/r2b-opus/`: hold1.out, hold2.out, hold2b.out, hold3.out, hc-check.log; image `r2b-opus-hcq12b`), merged image `zmerge6` (`~/work/bench/zrm6.sh`, zabrm-m6a/m6b.log), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (Round 2, R2B). Clean stack: spark6 `~/work/lanes/r3-prpack/` (tf = 0001-0024, patches 0021-0024, image `tensorfold-qwen38:zpr3-stack`, host tests `test-stack-fresh.log`).

---

**Title:** patches/0022: decode read-outs from a lossless 12-bit copy of their weights (decode +2.6 to +3.7% at 1 client, replies byte-identical)

**Body:**

## Description and Motivation

At decode widths every layer's hyper-connection read-out reads two bf16 matrices (attention and MLP `down`
[low (+ the inject rows), wide] and `up` [wide, low]): ~1.27 GB a round over 192 matrices, run by Triton's split
`_b16mm` with #49's fused `_reduce` + `_hc_act`, and `_hc_up_mix`. Those reads are bandwidth-bound, and bf16 spends 8
bits a weight on an exponent that varies little within a row.

`patches/0022-flash-next-readout-12bit-weights.patch` (`TF_FLASHNEXT_HC_Q12=1`):

- At load, a GPU packer (`tf_fn_hc_q12_pack_kernel`) builds a lossless 12-bit copy of each main-layer read-out matrix
  from its loaded bf16 rows. Per (row, 64 k) the largest exponent is stored once as a base; each weight keeps its
  sign|mantissa byte and a 4-bit exponent offset below that base; offset 15 escapes to the block's sorted list of exact
  bits. Over the checkpoint's read-out matrices 0.0155% of weights escape and a copy is 0.767 of the bf16 bytes (192 matrices,
  1266.2 -> 970.8 MB). The bf16 rows stay for prompt chunks and for every path the copy does not take.
- Decode windows of up to 32 rows run the down projection from the copy (`tf_fn_hc_down_q12_kernel`: one warp an
  8-column tile and K slice of 320, the same `mma.m16n8k16` chain Triton's split `_b16mm` issues, the same fp32
  partials; up to 8 rows the CTA that finishes a column group last sums the slices in order and applies
  `tf_fn_hc_reduce_act_kernel`'s operations), and windows of up to 16 rows the up projection and mix
  (`tf_fn_hc_upmix_q12_kernel`, `_hc_up_mix`'s bytes). Not the MTP layer or the final mixer (the 4-bit draft matrices
  read their 32-group sums), not two ranks, not recorded-launch tests.
- `tensorfold hc-check MODEL` (no weights) compares the copies' kernels with the kernel set's, byte for byte, then
  times both. The boot log says `hc q12: decode read-outs from 12-bit copies: 192 matrices, ...`.

Why the replies do not change: decoding the copy gives the bf16 weights bit for bit, and each output is the same MMA
chain from a zero accumulator, summed in the same slice order with the same epilogue operations.

Kernel time (hc-check, GB10, per read-out): 64.4 -> 51.5 us at 1 row, 63.6 -> 52.0 at 8, 64.2 -> 52.5 at 16; over 97
read-outs a round, 6.24 -> 4.99 ms.

Measured on one DGX Spark through the recipe's own server: the campaign's build with #34-#36 and #42-#50 (`zmerge5`)
against the same build plus this patch (a lane image), two holds of a warm-up boot then base / q12 / q12 / base, so
four boots an arm. Greedy, thinking off, 512-token replies, client-side per-request tok/s, per boot:

| | base | with `0022` | change |
| --- | --- | --- | ---: |
| code, 1 client | 127.9 / 128.0 / 127.8 / 127.9 | 131.2 / 130.4 / 131.3 / 131.4 | +2.6% |
| prose, 1 client | 72.2 / 72.6 / 72.0 / 72.5 | 75.0 / 75.0 / 75.1 / 75.1 | +3.7% |
| prose, 2 clients | 59.9 / 60.0 / 59.7 / 59.3 | 61.3 / 61.4 / 60.5 / 61.0 | +2.3% |
| code, 2 clients | 88.5 / 90.1 / 89.2 / 88.8 | 89.5 / 90.1 / 90.9 / 90.9 | +1.7% (one pair tied) |
| prose, 4 clients | 39.5 / 39.6 / 38.8 / 39.6 | 40.4 / 39.6 / 40.2 / 40.5 | +1.9% (one pair tied) |

In the first three rows every boot with the patch is faster than every boot without. Code at 4 clients is within the
noise (+0.6% leaving out one slow-plan boot in each arm, whose boot cost table timed the 32-row shared window at 91-93
ms instead of ~71). The kernel-level saving (~1.2 ms of a ~38 ms one-stream round) matches the 1-client gain.

Measured and left out: 2-4 tiles a warp, persistent double-buffered CTAs, the fused reduce above 8 rows, and the up
copy above 16 rows (each slower), and a bf16 CUDA port of the same kernels (no gain).

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

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the reference on every boot of every hold quoted here. (all 6 boots with the patch, every base boot.)
- `hc-check` on GB10: EQUAL on all 675 cases (partials, act, inject and mixed bytes against the split `_b16mm` +
  `tf_fn_hc_reduce_act_kernel` and `_hc_up_mix` / `_b16mm` + `_hc_mix`; 1-128 rows, with and without inject rows;
  normal weights, weights over 44 binades (millions of escapes), and every bf16 bit pattern; normal, wide and
  cancelling inputs; the fused and unfused reduce). Its built-in mutant (the k16 chunks reversed in each block) is
  caught in 30 of 36 cases, and the check fails unless it is caught at least once. That mutant still gives golden 6/6
  (greedy decoding absorbs last-bit fp32 changes), which is why the byte check, not the golden replies, is the gate.
  An engagement mutant (every projection zero, a switch in the measured image, not in this patch) gave golden 0/6, so
  the path runs.
- The patch here is the measured code without the engagement mutant's switch (named below) and with the boot line and comments reworded. The whole stack, `patches/0001`-`0024`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 190/190 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: +0.97 GB of device memory for the copies, allocated before the engine sizes the KV pool (the pool is that
  much smaller; the floor `TENSORFOLD_MEMORY_RESERVE_GIB` is unchanged). The startup estimate line was not
  re-checked separately.

Other PRs from me: #34, #35, #36 and #42-#50 (`patches/0010`-`0020`), and in this batch #[0021's PR] (the sliced-fill fix), #[0023's PR] (indexer select and prompt scores tile), #[0024's PR] (FP8 prompt tiles and int4 prompt gate/up), #[the 4096-row setting's PR] (4096-row prompt chunks). `patches/0021`-`0024` are written in that order on top of `0001`-`0020`: each applies with `git apply` after the ones before it, so this PR's patch needs #35, #36, #42-#50, #[0021's PR] merged first (logically it needs only #49's fused reduce + activation, whose operations its down kernel repeats). All of them add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35, #36 and #42-#50 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [ ] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
