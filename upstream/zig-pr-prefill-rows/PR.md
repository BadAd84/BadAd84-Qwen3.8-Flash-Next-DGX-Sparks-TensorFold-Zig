# Upstream PR (not posted): config: TF_FLASHNEXT_PREFILL_ROWS=4096 on one Spark

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0); batch 2 open as #42-#50.
Evidence: W7 settings re-check on zmerge5 (`merge/mverify10.sh`), the zots5 runs (`zarm2.sh`, 2026-10-08), merged image `zmerge6` (`~/work/bench/zrm6.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (2b and the W7 re-check). Settings only: no patch.

---

**Title:** config: TF_FLASHNEXT_PREFILL_ROWS=4096 on one Spark (cold prefill +0.3 to +3% on prose, +11% on 32k of code, replies byte-identical)

**Body:**

## Description and Motivation

`scripts/config.sh` now sets `TF_FLASHNEXT_PREFILL_ROWS=4096`: prompts run in chunks of 4,096 rows instead of the
engine's one-GPU default of 2,048. The engine's own comment already says 4,096 rows a call are faster than 2,048 at two
ranks; on one Spark the gain is smaller but holds. Any chunking gives the same bits (the engine says so, and the
bench's reply shas agree).

Measured on one DGX Spark through the recipe's own server, the campaign's build with #34-#36 and #42-#50
(`zmerge5`), a warm-up boot then 2048 / 4096 / (two boots of another setting) / 4096 / 2048, golden 6/6 on every
boot; cold prompts of new text, tok/s, one run a boot:

| | 2,048 rows | 4,096 rows |
| --- | --- | --- |
| 32k | 2,846 / 2,856 | 2,935 / 2,864 |
| 128k | 2,588 / 2,577 | 2,650 / 2,595 |

Every 4,096 run is above every 2,048 run (+0.3 to +3%); decode unchanged. On an earlier build (the stock engine with
`0010` and `0011`, two boots an arm): 128k 2,571 / 2,586 -> 2,622 / 2,622 (+1.4%, every 4,096 boot above every 2,048
boot), 32k 2,727 / 2,853 -> 2,848 / 2,867 (+0.5%, inside the boot spread), 8k no change; copy and rewrite replies
unchanged. Larger chunks amortise less than they used to once #42's n-gram host gather landed: before it, 4,096 rows
cut 128k prefill time by 5.9%.

The prompts above are prose, which routes to fewer experts than code: on 8k of real source code a 2,048-row chunk
touched a median of 328 distinct experts a layer against 110 for the prose. On real text the setting matters more: an
offline `bench` of 32k prompts (two runs x two reps an arm, in two holds, so this comparison crosses holds) gave code
2,485 tok/s at 2,048 rows and 2,755 at 4,096 (+11%), prose 2,859 and 2,945 (+3%).

It is one of the settings in the RigMark and time-to-first-token comparison below (the "+ this batch" column).

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
- The A/B: each arm a fresh boot of the recipe's server with the setting in the environment, arms interleaved.
- The RigMark / TTFT sweeps below booted and served RigMark's 64K prompts and the 120k TTFT prompts with it, at the
  recipe's defaults (`PARALLEL` 8).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: a 4,096-row chunk's prompt scratch is larger than a 2,048-row one's. The servers above started and served
  120k prompts at the defaults; I did not compare the startup estimate lines separately, so the box is unticked.

Other PRs from me: #34, #35, #36 and #42-#50 (`patches/0010`-`0020`), and in this batch #[0021's PR] (the sliced-fill fix), #[0022's PR] (12-bit read-out weights), #[0023's PR] (indexer select and prompt scores tile), #[0024's PR] (FP8 prompt tiles and int4 prompt gate/up). This one changes `scripts/config.sh`, the README's settings table and the CHANGELOG only; it works on the engine as it is (the setting is the engine's own) and needs none of them. All of them add CHANGELOG/README lines in the same places, and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [ ] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
