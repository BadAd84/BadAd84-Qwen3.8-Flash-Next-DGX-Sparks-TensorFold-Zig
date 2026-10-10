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
