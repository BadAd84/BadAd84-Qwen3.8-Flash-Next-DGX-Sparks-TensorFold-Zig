# Morning report (running file; written 2026-11-13 before the owner went to bed)

Ask for it by name. Newest status first. Everything below is current as of the "last updated" line; agents ran
overnight; see section 4.

Last updated: 2026-11-13, after all overnight agent runs finished. Nothing is posted anywhere outside our own repo.

## 1. What I need from you (decisions and approvals)

0. **Sampled decode and drafter-off measured (commit d221fe8):** drafter on beats `"draft": false` in 48 of 48 cells; PR unset is level with main; mxfp8 is +1..4% greedy but -2.0%/-1.2% on sampled chat at 1/2 streams (seed-dependent: +1.9% over 9 seeds). Draft PR comment with this, restyled and repaired: `work/pr0014/comment-sampled.final.md`, needs your approval before posting.
0. **PR OPENED: ashhart/TensorFold#3218** (Refs #3162; branch `BadAd84:flashnext-mtp-weights`, head `e16ca9d`, rebased on upstream `a3aecd8`; text as you approved, with the rebase-refreshed numbers shown to you). Watch for CI and the maintainer's reply on #3162 and #3218.
0. (earlier note) **The issue is POSTED: ashhart/TensorFold#3162** (your approved text). ATC cannot claim it: `atc check` returns `incomplete`
   (limitation `pullRequestsLimit`: over 300 open PRs, a fixed cap), so no claim was posted; no competing work exists.
   The PR is NOT opened. All three exactness equalities pass on main, PR unset and PR mxfp8 (`exact0014_summary.md`),
   and the PR body now says so with `Refs #3162`: `work/pr0014/PR-body-final-draft.md`. It needs your approval of the
   exact text (shown in chat), then I push the branch to the fork over SSH and open it.
1. (superseded by item 0 for the issue) **Approve or edit the upstream issue text** for the drafter setting: `work/issue0014/FINAL-issue.styled.md` (restyled
   through adam-style and repaired by me: identifiers, the 181.1 MB sizes, `"draft": false`, the stream table and the
   arrows restored; source text is `FINAL-issue.md`). Proposal template, all fields. It has the new naming `TF_FLASHNEXT_MTP_WEIGHTS=checkpoint|mxfp8`. Nothing is posted.
   After your approval I post it, run `atc check/claim`, and open the PR (text for the PR body is written after
   the receipt exists; it also needs your approval).
2. **PR defect fixed, receipt green:** on upstream main `mxfp8` failed with `FormatMismatch` (the recode window also
   caught the proposal head); the agent fixed it in two lines (reset the setting after the layer load). Branch
   `flashnext-mtp-weights` in `work/upmain`, signed commit `74c33dc`, BadAd84 identity, NOT pushed. Gates: fmt, pr_check
   (0 errors), lean 345/345, type-check, host suite 381/381 steps. Receipt on main vs branch: default level with main
   (-0.5..+0.2%), `mxfp8` +1.8..+3.1% on code at 1/2/4 streams, +2.3..+2.4% on chat at 2/4, flat on chat at 1 stream,
   golden 6/6, cold prompts flat. PR body: `work/pr0014/PR-body-final-draft.md` (intro restyled and repaired; the rest is the template's
   fixed form with measured numbers; needs your approval along with the issue text). Receipt files for `docs/receipts/flashnext-mtp-weights/` are in `work/rcpt/`.
3. **Patch 0007 (4-bit draft head default flip)** has the same upstream problem as 0014 had: it changes a default
   (`TF_FLASHNEXT_DRAFT_HEAD` affine4). For an upstream PR it should be a measured default change or an env setting
   in our recipe. Your call; I changed nothing.
4. **Capacity at the production window: DONE (patch 0015, `e081b7b`).** fp8 KV page pool: 6 and 8 streams now boot at
   262,144 and run byte-exact (golden 6/6, self-check 1,176 of 2,080, reply hashes equal to unpaged fp8 at 1/2/4):
   6 streams 144.2/204.8, 8 streams 160.5/234.3 (production 202.2/311.8 and 237.1/370.5, still 29-37% slower: the
   capacity gap is closed, the speed gap is the checkpoint plus ~4.5 ms engine). Opt-in `TF_FLASHNEXT_KV_PAGES`,
   cost at one stream about -0.3% (bf16 pages cost -2.4/-5.6%). **IMPORTANT correction found on the way:** three
   bugs in our patch 0003 meant every earlier "fp8 KV" cell actually ran bf16 caches (served streams ignored the
   engine's format), so earlier fp8 tables/claims are superseded by the new fp8pg2 cells (1/2/4 streams barely
   changed: 61.2/81.4, 86.2/120.4, 113.3/164.7). Follow-up done (`b550fbe`): Linux host suite passes as pristine, the fp8 device test passes (fails in v16: bug 2 proved), vision at fp8 pages answers an image correctly and identically to unpaged.
5. **Spend:** the agent has cost about $15 in this resumed run (plus the earlier $17); it keeps going on its queue
   until it finishes or is stopped (stop it with `write proc://RoundCostLever/kill`).
6. **One optional setting is on the table, measured and exact:** `TF_FLASHNEXT_GREEDY_WIDE=8` (the round width up to
   which greedy chains keep their depth, default 4). It is identical to the default below five streams - same
   counters to the digit at 1, 2 and 4 - and at six and eight streams it gives code 218.2 against 205.6/206.2 and
   247.8 against 235.9, while prose pays 0.5 to 1.1% there. Golden 6/6 with it on and off, self-check 1,176 of
   2,080 in every boot, so replies are unchanged. The series rule is no regression at any stream count, so I have
   recorded it in `patches/1.2.7/README.md` as an optional setting and NOT made it a default: your call whether a
   code-heavy multi-stream serve should take it. A repeat of the six and eight stream cells is queued behind
   `ExpertPass`'s run to tighten the prose figure.
7. Older open items (no change): deleting `ots/tensorfold-fp4port`, `ots/ai-engine` and `ots/tensorfold-gb10` on Gitea
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
- **The two serves run different models (verified in both config.json files on the box):** production's INT4-AutoRound
  checkpoint routes `num_experts_per_tok=5` with a 1280-wide shared expert, our NVIDIA FP4 checkpoint routes 10 with a
  640-wide one. Our round reads 2.35x production's expert bytes at one stream (4,699 MB vs 1,999 MB per round) and our
  expert kernels run at DRAM speed (213-222 GB/s, as fast as production's 199-217 at the same row counts). So much of the
  13-37% gap is the checkpoint, not our engine; no exact expert-kernel lever exists (the earlier "41 vs 25.5 ms" table was
  a boot-window artefact and is retracted in `docs/CATCHUP-1.2.6.md`).
- **Same-checkpoint comparison is impossible in both directions** (measured, `docs/CATCHUP-1.2.6.md`, section "The
  production target is a different model configuration"): our engine refuses production's INT4-AutoRound checkpoint
  (`UnsupportedCheckpoint`: modelopt only) and production's binary refuses ours (MXFP8 shared expert). Porting
  production's whole INT4 path (GPTQ layout, runtime routing width, int4 expert kernel, int4 head) is a project, not a
  lever. Each stack on its own checkpoint, one harness: ours is 18-39% slower (one stream 61.4/81.3 vs 74.5/131.0).
- **Where the 22 ms/round at one stream goes:** about 12 ms routing width (top-10 vs top-5), up to 5 ms head format
  (BF16 vs int4 head) - both the checkpoint's - and about 4.5 ms engine work on equal bytes, sitting in the dense
  projections and read-outs (production runs read-outs as q12 kernels; our `HC_Q12` is exact but flat).

**Decisions for you:**
- (a) Restate `production/SPEED-TARGET.md` as "each stack on its own checkpoint" (recommended; I have not edited it
  beyond the agent's note).
- (b) Whether to port production's INT4-AutoRound path onto our engine (large: GPTQ loader, comptime `slots=11`/`moe_w=640`
  made runtime on 245 lines in 57 files, int4 expert kernel and head). It is the only way to the production's own numbers
  on its own model. Not started.
- (c) Or accept NVFP4's cost as the checkpoint's and keep the 4.5 ms engine-owned part as the remaining target.

## 4. Running overnight

- Nothing is running. All agents are idle; spark6 production is up (`/health` 200).
- Agent tasks so far (PR fix and receipt, roofline, draft-policy sweep, expert-id traffic, same-checkpoint attempt)
  are finished. spark6 production serve is up (`/health` 200).
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
