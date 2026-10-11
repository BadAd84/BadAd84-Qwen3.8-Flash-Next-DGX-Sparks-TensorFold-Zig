# Upstream batch on the Zig release (current state)

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0). Posted 2026-10-09
~00:10 from the BadAd84 fork (owner-directed: "I want the outstanding PRs sent"), one signed commit each.

| Package | Upstream PR | What |
| --- | --- | --- |
| `zig-pr-confidence/` | #34 | `TF_FLASHNEXT_CONFIDENCE=-0.15` default (prose +7 to +10% at 1-2 clients) |
| `zig-pr-argmax/` | #35 | `patches/0010-flash-next-argmax-lse-rows` (OTS `ots0101`; +0.3 to +1%) |
| `zig-pr-mtp-fp8/` | #36 | `patches/0011-flash-next-mtp-fp8-overlay` + `tools/mtp_fp8.py` + `MTP_FP8` (OTS `ots0102`; code +4 to +5%) |

Not upstreamed: `ots0104` (boot cost tables on stdout: a diagnostic only). Candidate, not yet proven:
`TF_FLASHNEXT_PREFILL_ROWS=4096` (`docs/ZIG-SPEED-CAMPAIGN-2026-10.md` 2b).

Verification (2026-10-08 23:48-23:55, spark6): a clean clone of main with 0010 + 0011 through `PULL=0
scripts/prepare.sh` (image built, 320 kernels, the overlay written as the user), `start.sh` with -0.15, then
`tools/exact.py` PASS, `toolcheck.py` 3/3, `needle.py` correct at 199,730 tokens (`scripts/qwen38/zig/recipe_flow.sh`).
All three PRs touch CHANGELOG/README/CREDITS in the same places; #35 and #36 add rows to the same patch table:
rebase whichever merges second.

## Batch 2, posted 2026-10-10 (owner-approved)

| PR | Package | Patch |
|---|---|---|
| #42 | zig-pr-ngram-host | 0012 |
| #43 | zig-pr-copy-window | 0013 |
| #44 | zig-pr-copy-resync | 0014 |
| #45 | zig-pr-copy-shared | 0015 |
| #46 | zig-pr-seq-pool | 0016 |
| #47 | zig-pr-batch-draws | 0017 |
| #48 | zig-pr-fp8-fused-head-mt | 0018 |
| #49 | zig-pr-decode-glue | 0019 |
| #50 | zig-pr-draft-stop-lines | 0020 |

Each is a signed commit on a branch off upstream main; cross-references filled after posting.

## Batch 3, packaged 2026-10-11 (not posted)

Round 2's winners on the clean stack: spark6 `~/work/lanes/r3-prpack/` (tf = `~/work/zpr` 0001-0020 + 0021-0024,
host tests `test-stack-fresh.log` 21/21 steps 190/190, `mut0021.sh` killed), CPU image `tensorfold-qwen38:zpr3-stack`
(GPU verification pending). Experiment switches, unused kernel variants and lane names stripped (each PR says what).

| Package | Patch / setting | Source |
|---|---|---|
| zig-pr-fill-fix | 0021 (fix, `TF_FLASHNEXT_FILL=1` only) | r2d-fill `r2d-fill1.patch` |
| zig-pr-readout-12bit | 0022 + `TF_FLASHNEXT_HC_Q12=1` | r2b-opus `r2b-hcq12b.patch` |
| zig-pr-indexer-select | 0023 + `TF_FLASHNEXT_QSA_SELECT=1`, `TF_FLASHNEXT_QSA_TILE=4` | r2a-opus `r2a-qsa2.patch` |
| zig-pr-prompt-tiles | 0024 + `TF_FLASHNEXT_FP8_PROMPT_TILES=1`, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1` | r2c-fable `r2c-fp8tiles.patch` + `r2c-int4-prompt-gu.patch` (GU=2) |
| zig-pr-prefill-rows | `TF_FLASHNEXT_PREFILL_ROWS=4096` (settings only) | W7 re-check, 2b |

Every body carries the whole-stack RigMark + TTFT table (Python 0.6.1 / Zig 1.0.0 / + #34-#50 / + batch 3) from
`~/work/bench/zabrm-py-stock.log`, `zabrm-m5-stock-1010.log`, `zabrm-m6a.log`, `zabrm-m6b.log`.

## Batch 3, posted 2026-10-11 (owner-approved)

| PR | Package | Patch |
|---|---|---|
| #53 | zig-pr-fill-fix | 0021 |
| #54 | zig-pr-readout-12bit | 0022 |
| #55 | zig-pr-indexer-select | 0023 |
| #56 | zig-pr-prompt-tiles | 0024 |
| #57 | zig-pr-prefill-rows | settings |

The `#[the 4096-row setting's PR]` placeholder is not filled by upload_batch.py (it fills only numbered ones); it was
replaced with #57 by hand after posting.

## Review round 1, posted 2026-10-11 (owner-approved)

On #34-#36, #42-#50, #53-#57: one signed "Review round 1: <title>" commit on each PR branch that had a code change
(15; #34 and #57 had none), pushed without force, and one reply comment from `REVIEW-ROUND-1.md` (the batch note on
#34). #54 and #57: memory checkbox ticked. Script: `_ompscratch/v110/post_review_qwen.py`.
