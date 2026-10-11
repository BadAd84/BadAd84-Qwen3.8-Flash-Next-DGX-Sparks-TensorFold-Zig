# Upstream PR (not posted): patches/0023: the sparse-attention indexer's block lists from one read of each row, and its prompt scores on fma.rn.f32.bf16

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0); batch 2 open as #42-#50.
Evidence: lane r2a-opus (`~/work/lanes/r2a-opus/`: hold1.out, h2.out, h3.out, selcheck.log, scorescheck.log; image `r2a-opus-qsa2`), merged image `zmerge6` (`~/work/bench/zrm6.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (Round 2, R2A: note its R2A line quotes the other R2A lane's patch). Clean stack: spark6 `~/work/lanes/r3-prpack/` (tf = 0001-0024, patches 0021-0024, image `tensorfold-qwen38:zpr3-stack`, host tests `test-stack-fresh.log`).

---

**Title:** patches/0023: the sparse-attention indexer's block lists from one read of each row, and its prompt scores on fma.rn.f32.bf16 (cold prefill +4 to +9% at 100k-200k, decode -6.5% time a token at 200k; replies byte-identical)

**Body:**

## Description and Motivation

Flash Next's sparse attention first picks, for every row, the TOP key blocks by an indexer score (`_scores`), then
lists them in block order (`_select`, or `_select_tiles` past `_select`'s registers). At long contexts both grow with
the context: in an eager profile at 200k, decode select took 2.04 ms of a 47.8 ms round and the MTP steps' select 0.55
ms; a 2048-row prompt chunk spent 75.4 ms in `qsa_scores` and 40.8 ms in `qsa_select`.

`patches/0023-flash-next-indexer-select-scores-tile.patch`:

- `TF_FLASHNEXT_QSA_SELECT=1`: the block lists of decode windows, MTP steps and prompt blocks come from a new kernel
  file, `fn_qsa_stream.cu`. Each row's scores are read once, in block order, through a shared-memory candidate buffer
  that always holds the TOP best of the prefix seen so far (a later block must beat the current cut); an overflowing
  buffer is compacted by a 3-pass radix cut over the top 11/11/10 bits, and the last compaction emits the list in
  block order. Ties go to the lower block id, as in `_select`. Two kinds: `s5` (one 512-thread CTA a row) and `cs4`
  (a cluster of 4 CTAs a row, each cutting its slice to its own TOP, rank 0 merging them over distributed shared
  memory). Decode uses `cs4` from 32,768 blocks (~131k keys) and `s5` below; prompt blocks use `s5`. Off (`0`), the
  Triton kernels run as before.
- `TF_FLASHNEXT_QSA_TILE=4`: the prompt indexer's scores (`fn_qsa_scores.cu`, already in the engine) gain four tiles
  4-7 that compute the per-dim products with `fma.rn.f32.bf16` on the packed bf16 words, the PTX instruction
  `_scores` itself uses, in its order, instead of widening each operand to fp32 first. Tile 4 is the 2 x 4 shape.
- `qsa-check` also compares every `fn_qsa_stream` kind and every score tile with `_scores` / `_select` at decode
  windows (1, 3, 16 rows, bucketed and exact key counts, positions 2,045-261,000) as well as prompt blocks, and times
  them. The boot log says `qsa select: ...`.

Why the replies do not change: the lists are integers fixed by the scores (any exact selection gives the same words,
ties included), and the score tiles compute the same fp32 words as `_scores` (`fma.rn.f32.bf16(k1, q1, -0.0)` equals
`mul.rn(k1, q1)` exactly, and bf16 widens to fp32 exactly).

Kernel times on GB10 (`qsa-check`): one decode row at 200k, Triton `_select_tiles` 0.2085 ms, `cs4` 0.0246, `s5`
0.0347; 16 rows at 8k, `_select` 0.0106 ms, `s5` 0.0069, `cs4` 0.0143 (hence the split); a 256-row prompt block at
200k, the engine's select 1.061 ms, `s5` 0.297. Tile 4 scores 131k keys 2.42x faster than Triton `_scores` (tile 0,
the engine's default until now: 1.71x).

Measured on one DGX Spark: the campaign's build with #34-#36 and #42-#50 (`zmerge5`) against the same build plus this
patch (lane images), golden 6/6 on all 5 server boots. Eager profile at 200k: decode select 2.038 -> 0.337 ms a round, MTP
select 0.554 -> 0.089 ms, the round 47.82 -> 44.71 ms (64.4 -> 68.9 tok/s, the same rounds and reply sha); per 2048-row
chunk, `qsa_scores` 75.40 -> 53.45 ms and `qsa_select` 40.80 -> 15.81 ms. Offline prefill (`bench`, graphs, two runs
an arm, on a first build of the patch that ran `cs4` at every decode width; every run with it above every base run),
tok/s:

| | base | with `0023` |
| --- | ---: | ---: |
| 100k | 2,517.7 / 2,634.9 | 2,738.0 / 2,749.9 |
| 128k | 2,604.8 / 2,594.8 | 2,695.3 / 2,688.5 |
| 200k | 2,440.8 / 2,432.7 | 2,585.6 / 2,584.7 |

Through the recipe's server (cold prompts of new text, two boots an arm): 128k 2,569 / 2,563 -> 2,695 / 2,659 tok/s
(+4.2%), 200k 2,403 / 2,421 -> 2,549 / 2,535 (+5.5%). Decode at 200k (offline, 256 tokens): 15.08 / 15.49 -> 14.18 /
14.22 ms a token (-6.5%, the same first build); at 100k and 128k the arms overlap, so no decode claim there.

Measured and left out: cluster selects of 8 and 16 CTAs a row (8 is 3-10x slower than `s5` at prompt blocks; 16 is not
a portable cluster size), another one-CTA select (wrong lists on random-bit scores in 446 of 488 cases, and 2-3x
slower), the new score tiles at decode widths (Triton's `_scores` is faster at 1-16 rows), and two further
`fn_qsa_stream` shapes (`k6v8`, `c8k4v4`; exact, not picked).

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

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the reference on every boot of every hold quoted here. Offline bench reply shas identical in every arm at 100k, 128k and 200k.
- `qsa-check` on GB10 (the lane's build, which also held the kinds left out above): PASS, 1,704 EQUAL, 0 DIFFER: every
  select kind and score tile against Triton `_scores` / `_select` on random, tie-heavy and special (NaN, inf, -0,
  subnormal) indexer inputs, at prompt blocks (256 rows, positions 1k-261k) and decode windows.
- A standalone select check against a literal host replay of `_select` (all 2,052 key-list words, lengths and flags; 8
  input kinds x 62 shapes): every kind 496/496 EQUAL; six mutants (the tie rule `<=`, a 9-bit digit, the append order,
  the gather order, and two more) all killed. A standalone score check: 96/96 bytes equal; the mutant (the fma order
  of k1 and k0 swapped) differs in all 8 of its cases.
- The patch here is the measured code with the kinds and switches left out above taken out: one setting (`TF_FLASHNEXT_QSA_SELECT`) in place of the lane's bit mask and per-kind switches, and `qsa-check`'s case count changes with the kinds. The whole stack, `patches/0001`-`0024`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 190/190 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (the select kernels use shared memory only).

Other PRs from me: #34, #35, #36 and #42-#50 (`patches/0010`-`0020`), and in this batch #[0021's PR] (the sliced-fill fix), #[0022's PR] (12-bit read-out weights), #[0024's PR] (FP8 prompt tiles and int4 prompt gate/up), #[the 4096-row setting's PR] (4096-row prompt chunks). `patches/0021`-`0024` are written in that order on top of `0001`-`0020`: each applies with `git apply` after the ones before it, so this PR's patch needs #35, #36, #42-#50, #[0021's PR], #[0022's PR] merged first (logically it needs none of them). All of them add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35, #36 and #42-#50 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
