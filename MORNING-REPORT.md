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

## 3. What the measurements say about the gap (updated)

- Dense and expert BYTES are the same in production's INT4-AutoRound checkpoint and our NVFP4 one, and our expert
  kernels run near roofline (`fact_*` at 75-83% of GB10's 273 GB/s; production's `int4` kernels at 266 GB/s). So it is
  NOT a kernel-speed or checkpoint problem.
- **It is the draft policy:** our round verifies ~50 rows to accept 3.5 tokens (reading 14.2 GB of expert weights a
  round, 4.06 GB per accepted token); production verifies ~4 rows for 2.75 tokens (6.8 GB a round, 2.47 GB per token).
  Drafts are proposals, so tuning this is exact. Patch 0010 (price a round from the environment) is the mechanism and
  has never been run priced; the agent is sweeping it now (`ROUND_MS`, `DRAFT_ROW_MS`, `CONFIDENCE`, depth) on our
  engine. Production's own env block costs our binary ~9%, so the settings must be tuned here, not copied.
- Drafter in MXFP8 (patch 0014) is the other measured gain (+3.8/+7.6% at one stream on v1.2.7).
- Spend so far this resumed run about $28 (agent, one job); the sweep is a bounded task (about 80 requests).

## 4. Running overnight

- Agent `RoundCostLever`: (a) the `FormatMismatch` fix and the PR receipt run on upstream main
  (`~/work/target/receipt0014.sh`: main vs branch, upstream's own bench tools at 1/2/4 streams, golden, cold
  prompts); (b) the NVFP4 expert path roofline and an exact port.
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
