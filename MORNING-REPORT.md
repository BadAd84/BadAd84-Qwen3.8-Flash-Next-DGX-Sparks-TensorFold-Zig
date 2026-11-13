# Morning report (running file; written 2026-11-13 before the owner went to bed)

Ask for it by name. Newest status first. Everything below is current as of the "last updated" line; the agent
(`RoundCostLever`, opus5-max) and spark6 keep working while you sleep.

Last updated: 2026-11-13 (session end of day).

## 1. What I need from you (decisions and approvals)

1. **Approve or edit the upstream issue text** for the drafter setting: `work/issue0014/FINAL-issue.md` (proposal
   template, all fields). It has the new naming `TF_FLASHNEXT_MTP_WEIGHTS=checkpoint|mxfp8`. Nothing is posted.
   After your approval I post it, run `atc check/claim`, and open the PR (text for the PR body is written after
   the receipt exists; it also needs your approval).
2. **PR defect fixed, receipt green:** on upstream main `mxfp8` failed with `FormatMismatch` (the recode window also
   caught the proposal head); the agent fixed it in two lines (reset the setting after the layer load). Branch
   `flashnext-mtp-weights` in `work/upmain`, signed commit `74c33dc`, BadAd84 identity, NOT pushed. Gates: fmt, pr_check
   (0 errors), lean 345/345, type-check, host suite 381/381 steps. Receipt on main vs branch: default level with main
   (-0.5..+0.2%), `mxfp8` +1.8..+3.1% on code at 1/2/4 streams, +2.3..+2.4% on chat at 2/4, flat on chat at 1 stream,
   golden 6/6, cold prompts flat. PR body draft: `work/pr0014/PR-body-draft.md` (not yet restyled; needs your approval
   along with the issue text). Receipt files for `docs/receipts/flashnext-mtp-weights/` are in `work/rcpt/`.
3. **Patch 0007 (4-bit draft head default flip)** has the same upstream problem as 0014 had: it changes a default
   (`TF_FLASHNEXT_DRAFT_HEAD` affine4). For an upstream PR it should be a measured default change or an env setting
   in our recipe. Your call; I changed nothing.
4. **Capacity at the production window:** 6 and 8 streams do not start at fp8 KV and 262,144 tokens (the engine's
   page pool is refused with fp8 KV by one guard line, and the page geometry is bf16 rows). It needs new code (fp8
   page layout plus attention kernels reading through the page table). Do you want that built? Not started.
5. **Spend:** the agent has cost about $15 in this resumed run (plus the earlier $17); it keeps going on its queue
   until it finishes or is stopped (stop it with `write proc://RoundCostLever/kill`).
6. Older open items (no change): deleting `ots/tensorfold-fp4port`, `ots/ai-engine` and `ots/tensorfold-gb10` on Gitea
   after the salvage bundles (needs your word); the three serve repos' `REPO-FORMAT.md` work orders are with their
   agents.

## 2. Where the speed stands (spark6, NVFP4, one binary per row)

Accepted exact stack on TensorFold v1.2.7 (patches 0001-0007, replies identical, window self-check 1,176 of 2,080),
fp8 KV and a 262,144 window; aggregate tok/s prose / code against production's target:

| streams | ours | production | gap |
|---:|---|---|---|
| 1 | 61.8 / 81.7 | 70.9 / 113.0 | -13% / -28% |
| 2 | 87.6 / 120.8 | 103.3 / 173.7 | -15% / -30% |
| 4 | 113.4 / 166.7 | 162.3 / 254.0 | -30% / -34% |
| 6 | 146.2 / 205.3 (131,072 window) | 202.2 / 311.8 | -28% / -34% |
| 8 | 163.3 / 233.3 (131,072 window) | 237.1 / 370.5 | -31% / -37% |

Patch 0014 (drafter linears in MXFP8, selectable) adds +3.8% / +7.6% at one stream on top (not in the table).

## 3. What the measurements say about the gap (updated again, overnight)

Established (each with logs on spark6 and a section in `docs/CATCHUP-1.2.6.md`):
- Dense and expert BYTES are the same in production's checkpoint and ours; the hyper-connection read-outs are at
  roofline on our side (177 GB/s); read-out levers (12-bit copies, wide tile, half tiles) are all flat.
- The drafter's BF16 weights were real cost: patch 0014 (MXFP8, selectable) gives +3.8/+7.6% at one stream on v1.2.7,
  and +1.8..+3.1% on upstream main (where the baseline is faster and the drafter a smaller share).
- Draft policy is NOT the lever: 11 priced/confidence/depth/copy configurations are inert or negative on our engine
  (default CONFIDENCE -0.4 beats production's -0.15 by 6% on prose; priced rounds change no decision). A round costs
  38 ms plus 3.75 ms a row (prose). Verify rows a round are ~5 for us (the metrics counter), about the same as
  production, so my earlier "50 rows vs 4" claim was wrong (the agent corrected it; the 50 was expert-plan pairs).
- Production's expert path costs 25.5 ms a round, ours 41-43 ms, for the same ~5 rows. Our `fact_*` kernels stream at
  75-83% of peak by the instrument's byte count, but the two stacks' byte counts are not on the same basis (ours counts
  plan items, which includes cache reuse; production's looks unique), so "same bytes, 70% slower" is NOT yet explained.
  Candidates: our waves + fact passes read the same experts twice from DRAM; a different split of rows between the
  two kernels. Unmeasured: unique-expert DRAM traffic per round.

So the largest remaining item is the expert path (17 ms of the ~19 ms forward gap). Agent `ExpertPass`
(opus5.5-max) was dispatched overnight to measure unique-expert DRAM traffic and passes per expert on both stacks and
build an exact patch 0015 or prove why none exists. Stop it with `write proc://ExpertPass/kill` if you want to cap spend
(budget about 90 requests, roughly $15-30).

## 4. Running overnight

- `ExpertPass` (expert path investigation, patch 0015). Earlier agent tasks (PR fix and receipt, roofline, draft-policy
  sweep) are finished. spark6 production serve is up (`/health` 200) between agent runs.
- spark6 production serve is restored after each stage (`/health` 200 at last check).
- The upstream benchmark found that upstream main alone decodes bench_openai's code prompt at ~71.8 tok/s at one
  stream (our v1.2.7 stock is ~54 on our own harness: different prompt and base, not comparable yet; the receipt
  compares main to main plus the PR only).

## 5. Where things are

- Campaign repo `main`, pushed (Gitea + GitHub): `patches/1.2.7` (14 patches, README has every table), `docs/CATCHUP-1.2.6.md`,
  `patches/1.2.6` (same levers on v1.2.6). `production` branch = the serving recipe and target.
- Retired fork bundles: `archive/tensorfold-levers124/`, `archive/tensorfold-fp4port/`.
- Upstream PR work (unpushed): `work/upmain` branch `flashnext-mtp-weights`; issue text `work/issue0014/FINAL-issue.md`.
- Other repos' work orders: `REPO-FORMAT.md` in the DeepSeek, GLM-Python and GLM-Zig repos.

## 6. Risks and loose ends

- The WSL ext4 volume went read-only earlier (Linux host-suite runs not repeatable there); I did not run
  `wsl --shutdown` because other agents have jobs in WSL. Windows host suite runs work.
- Do not assume the receipt's pr-mxfp8 cells exist until the `FormatMismatch` fix lands (the first run's cells for it
  failed and are not data).
