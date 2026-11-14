# Morning report (running file; written 2026-11-13 before the owner went to bed)

Ask for it by name. Newest status first. Everything below is current as of the "last updated" line; agents ran
overnight; see section 4.

Last updated: 2026-11-14, after the INT4 port, drafter and multi-stream settings work. Nothing is running now. Nothing is posted anywhere outside our own repo.

## GAME PLAN (owner, 2026-11-14): "submit whatever we can as upstream issues/PRs, that's the entire game plan"

**#3218 round 3 POSTED (with your approval):** the branch is pushed (`8b5a008`, a plain push, no force; it carries one merge commit of main `2ba55ec`), the reply comment is up (issuecomment-6882229170) and the body is refreshed; the PR is MERGEABLE. Still waiting on the maintainer. **Still awaiting your 'post': the short reply to the maintainer on #3368** (licence facts: fn_int4.cu is Apache-2.0 from MiaAI-Lab's dual-Spark recipe, commit 04f2b53, plus the affine4 reason); text in `work/upsubmit/UpInt4Proposal/reply1.md`.

**MAINTAINER REPLIES (2026-11-14 evening), both positive:**
- **#3368 (INT4/GPTQ): YES.** "we'd take Flash Next on CUDA serving this checkpoint as stored ... Going ahead with step 1 is welcome." His rulings: config.json decides the widths (our option (c) is out), he leans to (b) (default shape stays a compile-time constant, engine generic over a widths struct, picked at load), GPTQ reader goes in core (#2460 item 7), his ordered series is 1 widths, 2 block-FP8 mixers, 3 core GPTQ reader, 4 int4 kernel, 5 admission/loading as stored, 6 MTP layer as stored; fidelity reference is a float reference of the published tensors (not another engine); refusals by name; kernel contract entries with planted controls; files at most 600 lines; receipts on current main; he will run the two-rank device check for step 1 himself. He asks us to name the recipe repository, commit and licence for fn_int4.cu (he says MiaAI notices are MIT, we said Apache-2.0: being verified). Agents: `Int4Port` is implementing step 1 locally; `UpInt4Proposal` is verifying the licence and drafting a short reply.
- **#3218 (drafter PR): positive, mergeable, four items before it lands:** re-pin four serving files in `gradient-serving.tsv` with `#3218:` notes; refuse mxfp8 on Metal/HIP before any checkpoint or device work (and make the test check position); name the measured branch commit in the receipt README; add resident memory main vs branch. Optional: CHANGELOG wording 'main's tokens a round on code'. Agent `PrMaintainer` is doing all of it locally; I will show you the commits and the reply before anything is pushed or posted.

Done: #3162 (issue, accepted in principle), #3218 (PR, follow-up posted; maintainer's agent will run its own device check) and **#3368 (the INT4/GPTQ proposal issue, posted 2026-11-14 with your approval; its Terms paragraph defines our engine vs the reference engine; the kernel credit to MiaAI-Lab is in the text; no maintainer reply yet)**. In preparation (agents never publish; each hands back local branches, receipts and DRAFT texts that you approve before anything is posted): `UpDraftHead` (the 4-bit draft head default, our 0007), `UpPromptReadout` (prompt read-out fusion, 0008, -3.5% cold 32k), `UpReadoutLevers` (0016-0019: first whether the 12-bit copy is lossless; lossy formats are banned upstream), `UpInt4Proposal` (a proposal issue only: GPTQ int4 as stored on Flash Next CUDA), plus `Fp4Confirm` part B (SHARED_DRAFTS/GREEDY_WIDE on upstream main alone; both settings already exist upstream). NOT submittable: fp8 KV (0003, 0015: a lossy cache format, banned upstream), flat levers (0001-0006, 0010-0013).

## 0. WAITING ON YOU (clean list, 2026-11-14; everything else below is status log)

Decisions (none blocks running work):
1. **Speed target.** Restate `production/SPEED-TARGET.md` as "each stack on its own checkpoint" (production serves a 5-expert INT4 model, ours a 10-expert FP4 one; neither engine loads the other's checkpoint). Recommended: yes.
2. **FP4 serve settings: launcher block or code-default flip.** Recommended launcher block `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8` (stack without HC_Q12; +4.1% mean, every cell no slower than defaults, replies identical). `Fp4Confirm` is repeating it ABBA now; the final block lands in `patches/1.2.7/README.md`. Say launcher block (recommended) or a code-default change in the series.
3. **Patch 0007 (4-bit draft head on by default; the whole decode gain, +8..12% at one stream).** Upstream's rule is new things default off. Options: keep it as our local default, make it a setting in our launcher, or file an upstream issue with a measured default change. Nothing changed so far.
4. **INT4 checkpoint.** Is the INT4-AutoRound model's quality acceptable to you? (Unmeasured by us.) Only if yes, and you want it on the upstream engine, does a proposal issue and a four-PR split make sense (runtime routing width is the hard part). Recommended: keep `patches/1.2.7-int4/` isolated, do not pursue.
5. **Upstream performance issue for `SHARED_DRAFTS=0 GREEDY_WIDE=8`.** `Fp4Confirm` part B measures it on upstream main alone; then your call whether to file.
6. **Strict refusal in #3218.** I posted that a CUDA drafter already stored as MXFP8 also refuses `mxfp8`. Tell me if you want it accepted instead (a new commit).
7. **Old Gitea repos.** Delete `ots/tensorfold-fp4port`, `ots/ai-engine`, `ots/tensorfold-gb10` and `tf-1.2.6-parity`? Salvage bundles exist for the first two; ownership of `tensorfold-gb10` is unknown.

Waiting on others, not you: the maintainer (his agent said it will run its own device check of unset/checkpoint/mxfp8 on #3218 and compare acceptance, resident memory, prompt and decode speed before merging; CI has not run; PR shows CONFLICTING on CHANGELOG.md, maintainers rebase at landing, force-push only if he asks).
Running now: `Fp4Confirm` (items 2 and 5). Production on spark6 is serving between windows.

## 1. Status log, newest first (older entries superseded)

0. **AN EXACT GAIN FOR OUR REAL (FP4) SERVE, no slower cell, settings only (commits 2516aad, 86c2947, 50de3d7):** `TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8`, keeping CONFIDENCE -0.4. Prose/code vs defaults: 2 streams +1.3%/+1.5%, 4 streams +0.8%/-0.0%, 6 streams +2.3%/+3.9%, 8 streams +1.5%/+5.0% (repeated), replies identical (hashes equal, golden 6/6 at one stream, self-check 1,176/2,080); one stream unaffected. Looser stop rules (-0.25, -0.15) LOSE at every stream count on FP4 (top-10 routing makes extra rows dearer). The `GREEDY_WIDE` prose-vs-code trade I asked you about is gone when combined with SHARED_DRAFTS=0. **Decision for you:** make these two the recipe default (an env block in our launcher, no code change) or flip the code defaults in the series; I recommend the launcher block now and a code-default patch only if you want it. The priced round (ROUND_MS) with the shared rule lifted does not beat it (checked at 4, 6, 8 streams; commit 322dfbb), so the price stays unset.
0. **DRAFTER GAP CLOSED ON THE SAME CHECKPOINT (settings only, replies identical):** on production's checkpoint the drafter was never the problem; our STOP RULE was. `TF_FLASHNEXT_CONFIDENCE=-0.15`, `DRAFTS_GREEDY=15` and, above one stream, `TF_FLASHNEXT_SHARED_DRAFTS=0` (multi-stream chains otherwise use a fixed 0.6 stop and ignore CONFIDENCE; found in `cuda_lanes_draft.rule`) lift ours to **1.00 / 0.97 of production at one stream** and 0.91 / 0.94 (2), 0.92 / 0.91 (4), 0.88 / 0.91 (6), 0.82 / 0.89 (8) prose/code, golden 6/6 identical to production's. Settings and tables in `patches/1.2.7-int4/README.md`. They apply to the INT4 checkpoint only as measured (on FP4, -0.15 cost 6% on prose at ONE stream). **This revises my earlier 'draft policy is inert' on the FP4 checkpoint: that finding was at one and four streams where the multi-stream override hid CONFIDENCE.** Running now: the same SHARED_DRAFTS=0 grid on the FP4 checkpoint at 2/4/6/8 streams (`Int4Port`), which could be a real exact gain for our actual serve.
0. **THE ANSWER TO YOUR INT4 QUESTION (commit a1ca44b, `docs/INT4-PORT.md`):** our engine, ported to production's own INT4-AutoRound checkpoint (`patches/1.2.7-int4/`), serves it with **golden 6/6 identical to production's own serve** (token hashes included). On the same checkpoint we run at **0.76 to 0.87 of production** (1 stream 61.3/105.8 vs 71.6/128.4; 8 streams 184.7/308.4 vs 242.4/380.0), against 0.62 to 0.84 on our FP4 checkpoint. So the checkpoint explains about **57 to 65% of the old gap on code and 20 to 46% on prose**; the rest is the engine: **fewer tokens a round (the drafter: 14% on code, 5% on prose at one stream)** and a round 3% (code) to 9% (prose) longer, from the dense projections with the read-outs (+4.8 ms a round); our int4 expert and head launches are 2.84 ms CHEAPER than production's. Running now: `Int4Port` on the drafter tokens-per-round gap (the biggest remaining item; exact by construction).
0. **Patches 0018 and 0019 landed too** (`854d3e4`): 0018 `TF_FLASHNEXT_READOUT_FUSE=1` (read-out glue fused into the product kernels, exact, +1.8% at 8 streams, inside noise below that, no extra memory; default off), 0019 the fused split's kernel contract. Host suite on a Linux filesystem passes on the 15, 17 and 19 patch trees.
0. **Patches 0016 and 0017 landed (`eac4000`), both exact, both off by default:** `HC_Q12` prefetch (0016) and `TF_FLASHNEXT_FUSED_SPLIT=1` (0017, production's fused out_proj form). Both together +0.4..+1.3%, no cell slower, golden 6/6 in 21 cells; each alone is inside the noise, and the 12-bit copies cost 1.07 GB of device memory, so they stay opt-in (setting: `TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1`). The 4.23 ms decomposes as read-out matmuls +1.75 (BF16 vs 12-bit bytes, drafter format), read-out glue +1.45, projections +1.03. Follow-up running: host test for 0016/0017 and the glue fusion (0018).
0. **OWNER DIRECTIVE (this evening): port the INT4-AutoRound path onto our engine to test whether the checkpoint/model is the whole speed gap (not for upstream unless it proves out).** Agent `Int4Port` (opus5.5-max, budget 160 requests, phased, commits at each phase: scope table, load and boot, int4 experts and head, same-checkpoint benchmark at 1/2/4/6/8 streams). Experimental series in `patches/1.2.7-int4/`, the accepted series is untouched. Stop with `write proc://Int4Port/kill`. `ReadoutGap` (the 4.5 ms engine-owned dense/read-out investigation, patch 0016) also runs; both take `gpu.lock`.
0. **Sampled decode and drafter-off measured (commit d221fe8):** drafter on beats `"draft": false` in 48 of 48 cells; PR unset is level with main; mxfp8 is +1..4% greedy but -2.0%/-1.2% on sampled chat at 1/2 streams (seed-dependent: +1.9% over 9 seeds). Draft PR comment with this, restyled and repaired: `work/pr0014/comment-sampled.final.md`, needs your approval before posting.
0. **PR #3218 UPDATED (all posted with your approval):** two new commits (`5038aec` refusals, blank test, docs row; `19224f8` receipt on main `06bcb989` and changelog) pushed with no force; the comment answering the maintainer's six points is up (issuecomment-6880191292) and the body is refreshed (head `19224f8`). One cell fails his noise rule as measured (chat, one stream, temperature 1.0, seed 1234: -1.0%, rerun -1.7%, a loss; +2.3% and +2.9% at two other seeds, +4.9% over nine); it is stated plainly in both. The PR still shows CONFLICTING on `CHANGELOG.md` (maintainers rebase at landing; a force-push only if he asks). Watch for CI and his reply.
0. **FP4 STACK, one arm, same window as production (commits 61a3004, d53d00b):** all exact switches on (`MTP_WEIGHTS=mxfp8 HC_Q12=1 FUSED_SPLIT=1 READOUT_FUSE=1 SHARED_DRAFTS=0 GREEDY_WIDE=8`) beat the defaults in all 10 cells by +1.8..+5.1%, replies byte-identical; against production on the SAME FP4 checkpoint we are -11%/-35% at one stream and -24..-30% prose / -30..-37% code at 2-8 streams (production reads faster on this harness than its own target table). Drop-one window: FUSED_SPLIT pays everywhere, READOUT_FUSE is a wash, and the best stack with no cell slower than defaults is **the stack WITHOUT HC_Q12** (+2.7..+5.7% every cell, mean +4.1%, no 12-bit copies, 309 pool pages instead of 294). Recommended launcher block for the FP4 serve: `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8` (each dropped arm ran once, so treat the ranking as indicative).
0. **UPSTREAM ACCEPTED THE DRAFTER SETTING IN PRINCIPLE (issue #3162, comment by the maintainer's agent, 2026-11-14):** "opt-in is fine under your gate ... Go ahead with the pull request" with six additions: receipts on current main (alternating), blank = unset = checkpoint with an off/on pair, accepted tokens per round beside tok/s, `mxfp8` must refuse by name where no MXFP8 projection exists, a noise rule (a cell is slower when both branch runs are under both main runs and the mean gap is over 1%; one rerun; a repeat is a loss), and a CHANGELOG line quoting the receipt. Note: by that rule our sampled chat cells at 1 and 2 streams (-2.0%, -1.2% at one seed) may count as losses; the agent measures several seeds and reports the truth. Agent `PrMaintainer` is making the follow-up commits LOCALLY (nothing pushed or posted); I will show you the commits, the receipt and the drafted comment for approval before anything goes to GitHub.
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
