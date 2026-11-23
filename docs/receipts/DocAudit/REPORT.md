# Doc audit: the Qwen repo against the current decisions

Read-only audit of the documentation in `C:/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig`. No file
outside `work/DocAudit/` was written, nothing was committed, and no doc was edited.

## Scope and method

Files read in full: `AGENTS.md` (285 lines, working tree), `README.md`, `scripts/qwen38/README.md` (the declared
SSOT), `docs/OPEN-PR-COVERAGE.md`, `docs/OVERLAP-1.2.6.md`, `docs/PROD-VS-ZIG-2026-11-18.md`,
`docs/QUALITY-A-VS-B-2026-11-18.md`, `docs/INT4-PORT.md`, `docs/SPEED-TARGET-1.2.6.md`,
`docs/GB10-THERMAL-BENCHMARK-METHODOLOGY.md`, `docs/UPSTREAM-WATCHLIST.md`, `docs/OVERNIGHT-1.2.6.md`,
`docs/AFFINE3-TILE-MISPICK-2026-11-06.md` and `docs/ENV-REGISTER.md` (as a source only).

The five longest dated records were read section by section against their own headers, so no section is
unexamined: `docs/CATCHUP-1.2.6.md` (all 1,538 lines except the tail of the per-tensor kernel table at 1,440 to
1,470), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (its 20 sections, with 45 to 260 and 300 to 320 read where they state a
verdict), `docs/PARITY-CAMPAIGN-1.2.4.md` (its 12 sections, with 95 to 330 read where they state a status),
`docs/RESEAT-d7c969c64.md` and `docs/RESTACK-main-964174ea05.md` (every table and verdict). A finding is reported
only where the section stating the claim was read. The package READMEs under `patches/` were read against
decision 6.

Excluded by instruction (another lane is editing them): `docs/ENV-REGISTER.md`, `scripts/qwen38/zig/target/env/dev.env`
and `scripts/qwen38/zig/target/env/register.env`. They were READ as sources of truth, never audited, and no finding
below targets them.

Sources of truth used for the "current truth" column: `scripts/qwen38/zig/target/env/dev.env` and `prod.env`,
`patches/*/README.md` and `CHANGES.md`, `git log --oneline -40`, and the measurement records in `work/`:
DevVsProd/RESULT.md, GapArms/RESULT.md, ProseDraft/RESULT.md, KnobTest/{RESULT,VERDICTS}.md, KvTierW3..W5,
KvTierShip/{RESULT,SHAPES}.md, KvTierDedup/RESULT.md, QInt4/RESULT.md, Int4Window/QUALITY-DEFECT.md,
Int4Respond/{RESULT,RESOLUTIONS}.md, PartFix/{REPORT,REBASE}.md, SpeedAudit/{REPORT-kimi,CORRECTIONS}.md,
SeriesR3/{REPORT,LEAN-DEBT}.md, SyncBench/{SUMMARY,SURVEY}.md, plus `work/KvTierRecon/DESIGN.md`.

Checks actually run (all read-only):

- `test -e` on every `scripts/`, `patches/`, `docs/` and `upstream/` path named anywhere in the audited files. Two
  of ours are missing (I5, L2); every other missing path belongs to another repo or to upstream TensorFold.
- `bash scripts/check-patch-packages.sh` reported `CLEAN (16 package dirs checked, 1 grandfathered)`, so AGENTS.md's
  first gate and the package shapes it describes are true today.
- `gh pr view N -R ashart/TensorFold` on the eight PRs decision 5 names: #4009, #3477, #3475, #3727 and #3413 are
  MERGED (2026-11-20 to 2026-11-21); #4075, #4183 and #4449 are OPEN. Decision 5 and decision 6 are confirmed.
- `diff` of `docs/SPEED-TARGET-1.2.6.md` against `production:production/SPEED-TARGET.md`.
- `grep -c '^export'` on `prod.env` (52) against the 54 that the 2026-11-23 records name.
- `wc -l` and `git diff HEAD` on `AGENTS.md`.

One state note: `AGENTS.md`'s gate bullet now carries the current rule ("every setting the served tree reads must be
SET in `dev.env`", `VERDICT-ONLY` failures, `update-env-register.py --defaults-from-tree`) and that correction is
UNCOMMITTED (`git diff HEAD -- AGENTS.md` shows 10 insertions, 6 deletions against `a470238b`). This audit treats the
working tree as current; the commit is owed, because the committed text still describes the retired four-verdict
model (`carried`, `default-ok`, `debt`, `unreachable`) that decision 1 replaces.

## Verdict key

| verdict | meaning |
|---|---|
| CONTRADICTS | the claim is false against the current truth |
| STALE-NUMBER | the shape is right, the number, date or sha is not |
| STALE-STATUS | a past state presented as current, or a superseded stack presented as the live one |
| MISSING-DECISION | the file must carry a current decision or fact and does not |
| CONFLICT-BETWEEN-DOCS | two documents disagree, both named in the row |

## Counts

| verdict | count |
|---|---:|
| CONTRADICTS | 17 |
| STALE-STATUS | 29 |
| MISSING-DECISION | 12 |
| CONFLICT-BETWEEN-DOCS | 7 |
| STALE-NUMBER | 3 |
| **total** | **68** |

Per file: AGENTS.md 6, README.md 5, scripts/qwen38/README.md 7, docs/CATCHUP-1.2.6.md 9, docs/INT4-PORT.md 6,
docs/OPEN-PR-COVERAGE.md 4, docs/OVERLAP-1.2.6.md 3, docs/PARITY-CAMPAIGN-1.2.4.md 3, docs/RESEAT-1ece6e6db.md 3,
docs/FP4-PORT-AND-RETEST.md 3, patches/main-1ece6e6db-r5/README.md 3, docs/SPEED-CAMPAIGN-2026-10.md 2,
docs/ZIG-SPEED-CAMPAIGN-2026-10.md 2, patches/1.2.6/README.md 2, docs/RESTACK-main-964174ea05.md 2, and one
each in docs/RECIPE-PATCHES-VS-UPSTREAM.md, docs/SPEED-TARGET-1.2.6.md, docs/OVERNIGHT-1.2.6.md,
patches/1.2.7/README.md, patches/main-1ece6e6db-r5-int4/README.md, docs/RESEAT-d7c969c64.md,
docs/QUALITY-A-VS-B-2026-11-18.md and scripts/patch-packages.list.

## The five most important findings

1. **The declared SSOT does not describe the serve.** `scripts/qwen38/README.md` is designated the SSOT by
   AGENTS.md:19, and 174 of its 238 lines document the retired Python serve. It never names `dev.env` or `prod.env`,
   the `patches/main-1ece6e6db-r5` series (with `-r5-int4` and `-r5-kvtier`), the INT4 arm, the NVMe KV tier, or
   `TF_FLASHNEXT_SHARED_DRAFTS=0`. A new reader cannot find the serve's environment, its levers or its measurements
   from the file the repo rules point at (C1 to C7).
2. **No doc records that our own build failed prompt following.** `work/Int4Window/QUALITY-DEFECT.md` measured, on
   both of our r2 arms, GSM8K falling from 96.8 to 8.8 percent (FP4) and 96.4 to 28.6 percent (INT4) because the
   build answers a few-shot example instead of the question. The r4 fix to 0008's shared-direct write-back is the
   prime suspect (the same lever produced a 0 of 20 answer set), r5 has never been re-measured for prompt
   following, and no doc mentions any of it (H6, V1).
3. **Two documents still say the shared-drafts knob loses.** `patches/1.2.6/README.md:38-41` lists `SHARED_DRAFTS`
   among the knobs that "move nothing or lose", and `docs/CATCHUP-1.2.6.md:1528-1538` says the gain "does not show
   on main at two and four streams" and "is no case for an upstream performance issue". Decision 2 promotes
   `TF_FLASHNEXT_SHARED_DRAFTS=0` on 7 to 11 percent at 2 to 8 streams and 54 percent of the prose gap, exact on
   every arm (P1, I1).
4. **`docs/OPEN-PR-COVERAGE.md` is two snapshots old and contradicts decision 5 outright.** It lists 278 open PRs
   and a 2026-11-08 verdict that no open PR covers any of our work; it names none of the seven merged PRs, none of
   #4075, #3218, #3523, #4183 or #4449, and it does not carry the part fix's or the int4 PR's pending work (D1 to
   D4).
5. **The repo's front matter still describes the spark4 Python serve.** `AGENTS.md:3` and `README.md:3` say the
   serve is on spark4, `AGENTS.md:18` says the scripts are copied to spark4, and `AGENTS.md:21` calls
   `patches/1.2.6` "EVERY change we own". The live serve is the Zig serve on spark6 at `:8888` and the current
   series is `patches/main-1ece6e6db-r5` on base `1ece6e6db` (A1, A2, A4, B1, B4).

---

# Findings, grouped by file

## AGENTS.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| A1 | 3 | "The Qwen3.8 Flash Next serve on spark4 as a development project" | The live serve is the Zig serve on spark6 `:8888` (`scripts/qwen38/README.md:3`); every 2026-11 measurement window runs on spark6 with production restored there (`work/ProseDraft/RESULT.md:3-8`, `work/KvTierShip/RESULT.md:3`, `work/DevVsProd/RESULT.md:3`). AGENTS.md:271 itself calls spark6 "the comparison box" | CONTRADICTS | `The Qwen3.8 Flash Next serve on spark6 (production at :8888) as a development project: our layers on the MiaAI-Lab recipe, their tests and benchmarks, and the upstream PRs.` |
| A2 | 18 | "`scripts/qwen38/` - the serve's files, AUTHORED here and COPIED to spark4 (`~/qwen-start.sh`, `~/qwen-ots/` for the image build, `~/work/` for the harnesses)" | Copied to spark6: `~/qwen6-start.sh`, `~/qwen-zig` (the recipe), `~/work/` for the harnesses (`scripts/qwen38/zig/qwen6-start.sh:2,20,42`; `work/KvTierShip/RESULT.md:3`). The spark4 Python serve is RETIRED (`scripts/qwen38/README.md:10-11`) | CONTRADICTS | ``- `scripts/qwen38/` - the serve's files, AUTHORED here and COPIED to spark6 (`~/qwen6-start.sh`, `~/qwen-zig` for the recipe, `~/work/` for the harnesses); the repo copy is the source. The env of record is `scripts/qwen38/zig/target/env/dev.env` for our arm and `prod.env` for production.`` |
| A3 | 19-20 | "`scripts/qwen38/README.md` is the SSOT for the serve and each layer's evidence" | That README documents the retired Python serve (lines 10 to 183) and the October Zig 1.0.0 campaign; it names none of the 14 settings in `dev.env` and neither env file (see C1 to C7) | CONFLICT-BETWEEN-DOCS | ``the repo copy is the source. The serve's settings are the two env files named above; `patches/*/README.md` carries each lever's evidence, and `scripts/qwen38/README.md` is the history of the retired Python serve and the October Zig campaign.`` |
| A4 | 21-24 | "`patches/1.2.6/` - EVERY change we own on TensorFold v1.2.6 (`6e9af9302`)" and the example `build_patches.sh ... 6e9af9302 patches/1.2.6` | The current series is `patches/main-1ece6e6db-r5` (0001 to 0020) on upstream main `1ece6e6db`, plus `patches/main-1ece6e6db-r5-int4` (0021, 0022) and `-r5-kvtier` (0021, 0022) (`patches/main-1ece6e6db-r5/README.md:1-5`, `work/KvTierShip/RESULT.md:19-24`). v1.2.6 is three releases behind (v1.2.7, v1.2.8 and v1.2.9, `docs/RESTACK-main-964174ea05.md:3-6`) | STALE-STATUS | ``- `patches/main-1ece6e6db-r5/` - EVERY change we own on upstream main `1ece6e6db` as numbered `.patch` files applied in filename order to a PRISTINE upstream tree, with `main-1ece6e6db-r5-int4/` (the INT4-AutoRound port) and `main-1ece6e6db-r5-kvtier/` (the NVMe KV tier) on top. `build_patches.sh TAG git://192.168.99.16/up-pr/tf <base-sha> <package>`. The v1.2.6 and v1.2.7 packages are historical. `` |
| A5 | 271 | "spark4 is stock DGX OS on a 1 Gb/s LAN link; spark6 (the comparison box) is the same" | spark6 is the production box AND the measuring box; spark4 is no longer a serve (`scripts/qwen38/README.md:10`, `work/ProseDraft/RESULT.md:3`). `docs/PROD-VS-ZIG-2026-11-18.md:92-94` records "spark6 has no passwordless sudo", which is a real constraint the current text does not carry | STALE-STATUS | `spark6 is stock DGX OS on a 1 Gb/s LAN link and has no passwordless sudo, so the :8888 firewall rule cannot be applied there and arms bind to 127.0.0.1 instead. Production restarts take about 2 min; the container restarts by itself after a reboot (``unless-stopped``).` |
| A6 | 3-40 (Branches, Layout) | The repo rules name the branches, the scripts, the patch packages and the archive, and never name an environment file or a promotion rule | Decision 1 makes the env the record: every setting the served tree reads must be SET in `dev.env`, and `docs/ENV-REGISTER.md` is being rewritten to say so. AGENTS.md's own Gate bullet (245-256) now enforces this, but nothing in Branches or Layout tells a reader where the serve's environment lives | MISSING-DECISION | Add a Layout bullet: ``- `scripts/qwen38/zig/target/env/` - the environment of record: `dev.env` is our arm (every setting the served tree reads, each with its citation, gate `check-dev-env.py`), `prod.env` is the live serve's launcher copy (52 settings, 2026-11-20). A setting with no value in the env is a hard stop at a rebase, not a note in the register. `` |

## README.md (repo root)

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| B1 | 3 | "Development of OTS's Qwen3.8 Flash Next serve on spark4 (`:8888`, one Spark)" | spark6 (`scripts/qwen38/README.md:3`; `work/ProseDraft/RESULT.md:3-8`) | CONTRADICTS | `Development of OTS's Qwen3.8 Flash Next serve on spark6 (:8888, one Spark): the MiaAI-Lab recipe, our levers as patches on upstream TensorFold main, their tests and benchmarks, and the upstream PRs.` |
| B2 | 10-16 | "## Now (2026-10-08)" says production is spark4 with the Python engine v0.6.1, image `tensorfold-qwen38:v061-ots`, started by `qwen-start.sh` | That serve is RETIRED (`scripts/qwen38/README.md:10-11`). Production today is the Zig serve on spark6, image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, and our arm is `patches/main-1ece6e6db-r5` + int4, at production's shape, 0.79 prose and 0.95 code of production at 8 streams (`work/DevVsProd/RESULT.md:12-20`) | STALE-STATUS | Replace the whole "Now" block with: `## Now (2026-11-23)` then two bullets: (1) `- **Production (spark6 :8888):** image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, INT4-AutoRound, fp8 KV, 8 streams at 262,144, its own launcher `~/qwen6-start-prod.sh`; the measured target is `production/SPEED-TARGET.md`.` (2) `- **Our arm (main):** `patches/main-1ece6e6db-r5` (+ `-r5-int4`, + `-r5-kvtier`) on upstream main `1ece6e6db`, env in `scripts/qwen38/zig/target/env/dev.env`; at production's shape it reads 0.79 prose / 0.95 code of production at 8 streams (`work/DevVsProd/RESULT.md`), and `TF_FLASHNEXT_SHARED_DRAFTS=0` is promoted (7 to 11 percent at 2 to 8 streams).` |
| B3 | 18-32 | The `docs/` list names five files: SPEED-CAMPAIGN-2026-10, UPSTREAM-WATCHLIST, ZIG-SPEED-CAMPAIGN-2026-10, GB10-THERMAL, FP4-PORT-AND-RETEST | `docs/` holds 20 `.md` files; the missing 15 include ENV-REGISTER (the gate's subject), INT4-PORT, OPEN-PR-COVERAGE, CATCHUP-1.2.6, PROD-VS-ZIG-2026-11-18, QUALITY-A-VS-B-2026-11-18, RESEAT-1ece6e6db, RESEAT-d7c969c64, RESTACK-main-964174ea05, SPEED-TARGET-1.2.6, PARITY-CAMPAIGN-1.2.4, OVERLAP-1.2.6, OVERNIGHT-1.2.6, RECIPE-PATCHES-VS-UPSTREAM, AFFINE3 | MISSING-DECISION | Add one bullet per missing file, in this order: `ENV-REGISTER.md` (the setting rule and its gate), `OPEN-PR-COVERAGE.md` (the PR map), `CATCHUP-1.2.6.md` (the 1.2.6/1.2.7 measurements), `INT4-PORT.md` (serving production's checkpoint), `PROD-VS-ZIG-2026-11-18.md` and `QUALITY-A-VS-B-2026-11-18.md` (the two 2026-11-19 windows), `RESEAT-1ece6e6db.md`, `RESTACK-main-964174ea05.md`, `RESEAT-d7c969c64.md`, `SPEED-TARGET-1.2.6.md`, `PARITY-CAMPAIGN-1.2.4.md`, `OVERLAP-1.2.6.md`, `OVERNIGHT-1.2.6.md`, `RECIPE-PATCHES-VS-UPSTREAM.md`, `AFFINE3-TILE-MISPICK-2026-11-06.md`. Each bullet is one line saying what the file records and whether it is current or historical. |
| B4 | 35-38 | "The serve: `qwen-start.sh`, `build_qwen_ots.sh`, the seven layers (`pr319/`, `ple-cache/`, `ple-native/`, `chain-stop/`, `mtp-graph/`, `ple-defer/`, `tokenize-nogil/`, each with its test and mutant runner)" | All seven layers build the RETIRED Python image `tensorfold-qwen38:v061-ots` (`scripts/qwen38/README.md:10-30`). The current serve is the recipe plus `patches/main-1ece6e6db-r5*`, its env, and `scripts/qwen38/zig/` | CONTRADICTS | ``The serve: the MiaAI-Lab recipe on spark6, our levers as numbered patches (`patches/main-1ece6e6db-r5*`), the environment (`scripts/qwen38/zig/target/env/`), the build and boot tools (`scripts/qwen38/zig/target/build_patches.sh`, `scripts/qwen38/zig/qwen6-start.sh`), the benchmarks (`scripts/qwen38/zig/bench/`), and the quality harness (`scripts/quality/`). The Python layers under `pr319/`, `ple-cache/`, `ple-native/`, `chain-stop/`, `mtp-graph/`, `ple-defer/` and `tokenize-nogil/` built the retired spark4 image and are kept as history.`` |
| B5 | 41 | "The seven recipe PR packages (`qwen-pr-*`: `pr.diff`, `PR.md`, `mutants.sh`)" | `upstream/` holds 43 package directories: the seven parked `qwen-pr-*`, plus `zig-pr-*` (about 20), `tensorfold-pr-*` (about 12), `round-3-2026-10-25`, `tensorfold-pr-2815`, and the batch files (`ls upstream/`) | STALE-NUMBER | `The parked recipe PR packages (`qwen-pr-*`, seven) and the Zig and TensorFold PR packages (`zig-pr-*`, `tensorfold-pr-*`) that followed them, each with its `RECORD.md` and `SHA256SUMS`; `BATCH-2026-10.md` and `compile_batch.py` write the batch texts.` |

## scripts/qwen38/README.md (the declared SSOT)

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| C1 | 3 | "started by `zig/qwen6-start.sh` (box copy `~/qwen6-start.sh`)" | Production is restored from `~/qwen6-start-prod.sh` in every window (`AGENTS.md:127-130`, `work/ProseDraft/RESULT.md:3-4` "restoring production from its own EXIT trap", `work/ProdVsZig`'s arm list). The repo carries no file of that name; the repo copy is `scripts/qwen38/zig/qwen6-start.sh`, which the box keeps under a different name. Two box files, one repo file, no statement of which one is authoritative | STALE-STATUS | ``**Live since 2026-11-07: the Zig serve on spark6 `:8888`.** Production is started by the box's `~/qwen6-start-prod.sh`, whose repo copy is `zig/qwen6-start.sh`.`` |
| C2 | 7 | "Boot 89 s, golden 6/6 identical to stock on the first boot" | 83 to 90 s is the production boot at 1, 2, 4, 6 and 8 streams (`docs/SPEED-TARGET-1.2.6.md:70-76`); the dev arms boot in 145.7 and 154.7 s with the pool and the tier (`work/KvTierShip/RESULT.md:51-52`). One unqualified number now reads as the serve's boot time | STALE-NUMBER | `Boot 83 to 90 s at 1 to 8 streams (`docs/SPEED-TARGET-1.2.6.md`); golden 6/6 identical to stock on the first boot.` |
| C3 | 10-183 | About 170 lines describe the Python serve, then the seven layers and their measurements, under one sentence "The Python serve below is RETIRED" | The layers are retired with it (`scripts/qwen38/README.md:10-11`). AGENTS.md:55 requires "retired things marked RETIRED in one line"; this is the opposite, and it buries the current serve | CONTRADICTS | Keep the one RETIRED line at 10, delete lines 12 to 183, and add: ``The layer evidence (pr319, ple-cache, chain-stop, ple-native, mtp-graph, ple-defer, tokenize-nogil, hc-split) is in `docs/SPEED-CAMPAIGN-2026-10.md` and `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`; the layer directories stay in the tree as history.`` |
| C4 | 140 | "Stock = `PREPARE=0 IMAGE=tensorfold-qwen38:zig-db28187` (the recipe's image and defaults, the campaign's 'stock')" | That image is the October Zig 1.0.0 release (`docs/ZIG-SPEED-CAMPAIGN-2026-10.md:1-3`). The current stock is upstream main at the series' base, built with no patches (`patches/main-1ece6e6db-r5/README.md:3-5,42-43`), and the last full A/B is `patches/main-964174ea05/README.md` | STALE-STATUS | `Stock, for the October campaign below, = PREPARE=0 IMAGE=tensorfold-qwen38:zig-db28187. The current stock is upstream main at the series' base (``build_patches.sh TAG git://192.168.99.16/up-pr/tf 1ece6e6db <empty package>``), and the last full A/B of the series is ``patches/main-964174ea05/README.md``.` |
| C5 | whole file | The SSOT names no environment file, and none of the 14 settings in `dev.env` appears anywhere in it | `dev.env` sets `TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_NO_UPDATE_CHECK`, `TENSORFOLD_VIDEO_TOKENS`, `TF_FLASHNEXT_BATCH_DRAWS`, `TF_FLASHNEXT_CONFIDENCE`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_WINDOW`, `TF_FLASHNEXT_PROMPT_SHARED_DIRECT`, `TF_FLASHNEXT_READOUT_FUSED`, `TF_FLASHNEXT_CHUNK_SOLO`, `TF_FLASHNEXT_CHUNK`, `TF_FLASHNEXT_WINDOW_CHECK`, `TF_FLASHNEXT_KV_PAGES`, `TF_FLASHNEXT_SHARED_DRAFTS` (`scripts/qwen38/zig/target/env/dev.env`); `prod.env` sets 52 | MISSING-DECISION | Add a section after the live block: ``## The environment`` then a table of all 14 `dev.env` settings with value, evidence path and note, plus ``prod.env``'s 52 launcher settings and the rule that a setting with no value is a hard stop (`AGENTS.md`, Gate). |
| C6 | whole file | The SSOT carries no record of the NVMe KV tier, which is measured and dev only: 8 streams at 262,144 with the page pool and a 6 GiB ask (3.1 GiB granted), appends resuming in 1.04 to 1.23 s against 44.2 to 44.7 s, exactness at equal depth proved at four depths, a rewrite costing a full prefill | `work/KvTierShip/RESULT.md:45-65,85-90`, `work/KvTierShip/SHAPES.md:49-59`, `work/KvTierDedup/RESULT.md:8-20`, `work/ProseDraft/RESULT.md` (the argument check), `dev.env:31-42` | MISSING-DECISION | Add: ``## The persistent NVMe KV tier (dev only)`` with the shape (8 x 262,144, ``TF_FLASHNEXT_KV_PAGES=4096``, ``--prompt-cache-gib 6`` and the planner's 3,166 MiB, the launcher's ``--prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20``), the resume numbers (1.042 and 1.226 s against 44.206 and 44.305 s), the exactness result at four depths, the append dedup (115.1 MiB a turn against 228.1), the boundary where it does not dedup (a reply plus message of 256 tokens or more), and that a rewrite costs a full prefill. |
| C7 | whole file | No record of `TF_FLASHNEXT_SHARED_DRAFTS=0` (promoted, 7 to 11 percent at 2 to 8 streams), nor of the prose residual (drafting volume, acceptance 0.718 against production's 0.750, not a policy stop) | `work/ProseDraft/RESULT.md:9-12,65-114,229-240`; `dev.env:43-49` | MISSING-DECISION | Add: ``## The prose gap`` with the source finding (``shared_stop = 0.6`` hard-coded at ``families/flashnext/cuda_lanes_draft.zig:26-30``, added upstream 2026-11-10, absent from the production engine), the promotion (S0 229.0 against 207.8 tokens a second at 4 streams prose, 300.1 against 276.8 code, 8 streams +6.9 percent, exactness on every arm, 54 percent of the gap), and the residual (2.8 drafted a round against production's 3.03, acceptance 0.718 against 0.750, so drafting volume in the drafter, not a stop and not solved). |

## docs/OPEN-PR-COVERAGE.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| D1 | 1-85 | The file is a 2026-11-12 snapshot ("278 open, 40 about Flash Next") plus a kept 2026-11-08 scan, presented as the PR map | Decision 5 and `gh pr view` (this audit): #3611, #3726, #3413, #2044, #4009, #3477, #3475, #3727 merged; #4075 clean awaiting their GB10 check; #3218 and #3523 awaiting device checks with nothing needed from us; #4183 answering a maintainer change request; #4449 a draft whose parent was rebuilt to `37d99a8a` | CONTRADICTS | Replace the whole file with: a dated header `## 2026-11-23: our PRs, state by state`; a table of every PR above with merged sha and date or its outstanding ask; a line saying nothing is needed from us on #3218 and #3523; a row for #4075; a row for #4183 naming the rebased head `984556bf50` on main `7bd7081e0`, the narrowed BF16 dense wrapper, the `prompt_down_bf16` coverage and the `int4-contract` dispatch committed, and the device summary as the outstanding piece; a row for #4449; a row for the part fix (`bbbf0d414` on `1c9688ca2`, gated, owner-approved text, awaiting the post-time re-seat, issue not yet opened); then the 2026-11-12 and 2026-11-08 scans, each under a heading that says it is history. |
| D2 | 8-15 | "Our 13 patches apply on v1.2.6 only: on v1.2.7 the first stops in `CHANGELOG.md`, on main in `CHANGELOG.md`, `cuda_lanes_load.zig`, `cuda_mtp_draft.zig` and `platform/environment.zig`" | The series is 20 patches on main `1ece6e6db`, re-seated and gated (`patches/main-1ece6e6db-r5/README.md:1-5,118-130`), plus two int4 and two kvtier patches (`work/KvTierShip/RESULT.md:19-24`) | STALE-STATUS | `Our series is 20 patches on upstream main `1ece6e6db` (`patches/main-1ece6e6db-r5`), with the INT4 and KV-tier packages on top; the 13-patch v1.2.6 series and the 19-patch v1.2.7 series are historical.` |
| D3 | 81-85 | "The recipe's 17 patches remain a genuine porting backlog: nobody upstream has submitted any of them against the 1.2.4 kernel layout. Our 0064/0065 are the only two features from the whole campaign that exist as reviewable diffs against upstream 1.2.4" | Seven of our PRs are merged, three more are open with device checks pending, and every lever of the 20-patch series exists as a patch against main (`gh pr view`, this audit; `patches/main-1ece6e6db-r5/README.md:52-77`) | CONTRADICTS | `The recipe's 17 patches are a porting backlog for the recipe's own 1.1.4 line only: our levers are a 20-patch series against upstream main plus eight pull requests (seven merged, one open awaiting a GB10 check), and the recipe's features are not part of that series.` |
| D4 | whole file | No row for the part fix (decision 8) | `work/PartFix/REBASE.md:1-30`: head `bbbf0d414b5ef05fd291812da2f8d49f0932998e` on `1c9688ca2`, one signed commit, 2 files +133/-2, gated, owner-approved text, awaiting the post-time re-seat, issue not yet opened | MISSING-DECISION | Add a row: `Part fix (MTP head fc_h lane sizing) | not opened | head `bbbf0d414` on `1c9688ca2`, 2 files +133/-2, host gates green | issue text ready, not opened; PR text approved; re-seat and post after the device gate` |

## docs/RECIPE-PATCHES-VS-UPSTREAM.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| E1 | 3 | "Checked against upstream `267c5af6a` (the tip our A/B arms ran) and today's tip `303c389d4a`" | "Today" has no date and upstream is now many releases past it: v1.2.7 `93a2e93ec` (2026-11-11), v1.2.9 `6b9de69510` (2026-11-15, `docs/RESTACK-main-964174ea05.md:3`), main `1ece6e6db` (2026-11-20) and later | STALE-STATUS | `Checked against upstream `267c5af6a` (the tip our 1.2.4 arms ran) and `303c389d4a` (the tip on 2026-11-06). This is a 1.2.4-era record; upstream is at v1.2.9 and later, and the current series is `patches/main-1ece6e6db-r5`.` |

## docs/OVERLAP-1.2.6.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| F1 | 8 | "v1.2.6 is `6e9af9302` (2026-11-10, the current release)" | v1.2.7 was tagged 2026-11-11 (`docs/OPEN-PR-COVERAGE.md:8`) and v1.2.9 `6b9de69510` on 2026-11-15 (`docs/RESTACK-main-964174ea05.md:3`) | STALE-STATUS | `v1.2.6 is `6e9af9302` (2026-11-10; it was the current release when this study was made, and v1.2.9 has since shipped).` |
| F2 | 9-11 | "The modern branch is now `1.2.6` in `ots/tensorfold-levers124` (tip `6e9af9302`); `main` there is the current production stack (zmerge8-kfix)" | The repository no longer exists (its own banner at line 3, and `AGENTS.md:25`); the production engine source is the `production` branch of this repo | CONTRADICTS | `The 1.2.6 tree was the branch `1.2.6` of the retired `ots/tensorfold-levers124`; it is preserved in `archive/tensorfold-levers124/levers124.bundle`, and the production engine source is the `production` branch of this repository.` |
| F3 | 52-63 | "Branch layout in ots/tensorfold-levers124 (2026-11-10)" lists branches of a repository the banner at line 3 says no longer exists | Same as F2 | CONFLICT-BETWEEN-DOCS | Delete the section, or retitle it `## Branch layout of the retired ots/tensorfold-levers124 (2026-11-10), restored from `archive/tensorfold-levers124/levers124.bundle``, and say in one line that none of these branches is a live reference. |

## docs/PARITY-CAMPAIGN-1.2.4.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| G1 | 7-11 | "the campaign's base is now `1.2.6` (`6e9af9302`) in `ots/tensorfold-levers124`, and `main` there is the current production stack" | The repository is retired (line 3 banner), and the base has moved twice more: `964174ea05` (2026-11-15) then `1ece6e6db` (2026-11-20, `docs/RESEAT-1ece6e6db.md:7-9`) | CONTRADICTS | `SUPERSEDED ... the base is now upstream main `1ece6e6db` (`patches/main-1ece6e6db-r5`); the 1.2.6 tree lives only in `archive/tensorfold-levers124/levers124.bundle`. Everything below is the 1.2.4-era record.` |
| G2 | 55-64 | "## Checkpoint route: DECIDED 2026-11-09 - NVFP4, no INT4 port" | The INT4 port exists and now serves production's own checkpoint on our engine: `patches/main-1ece6e6db-r5-int4/README.md` (build-time `slots = 6`, `shared_w = 1280`), built as `tensorfold-qwen38:pvz-int4` (`docs/PROD-VS-ZIG-2026-11-18.md:12,48-49`) and as `qr-b-r5int4-1ece6e6d` at production's shape (`work/DevVsProd/RESULT.md:12-27`) | CONTRADICTS | `## Checkpoint route: DECIDED 2026-11-09 (NVFP4 for the 1.2.4 port), REVERSED 2026-11-13` then one line: `The engine now serves production's INT4-AutoRound checkpoint through `patches/main-1ece6e6db-r5-int4`; the NVFP4 route remains the FP4 arm's (``patches/main-1ece6e6db-r5`` on `nvidia/Qwen3.8-Flash-Next-FP4-Local`).` |
| G3 | 86 | "Quality comparison: DONE - NVFP4 acceptable, no INT4 port (see above)." | Same as G2; and the 30-prompt comparison it refers to is superseded by `docs/QUALITY-A-VS-B-2026-11-18.md` (1,664 items) and then by `work/Int4Window/QUALITY-DEFECT.md` | CONTRADICTS | `- Quality comparison: DONE for the 1.2.4 route (NVFP4 acceptable), superseded 2026-11-13 when the INT4 port landed; the later 1,664-item window is `docs/QUALITY-A-VS-B-2026-11-18.md`.` |

## docs/INT4-PORT.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| H1 | 3-7 | "Re-seated 2026-11-15 onto upstream main `964174ea05` ... but it is not yet built into an image or served on that base, so every number below is the v1.2.7 package's (image `int4d`)" | It has been built and served twice: `tensorfold-qwen38:pvz-int4` at 1 to 8 streams (`docs/PROD-VS-ZIG-2026-11-18.md:12,48-49,102-108`) and `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` at production's shape (`work/DevVsProd/RESULT.md:12-27`, `work/QInt4/RESULT.md:9-11`); the r5 package is `patches/main-1ece6e6db-r5-int4` | STALE-STATUS | `**Re-seated 2026-11-20 onto upstream main `1ece6e6db`** as `patches/main-1ece6e6db-r5-int4/` (on r5's 0001 to 0020) and served as `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` at production's shape (8 x 262,144, fp8 KV, production's 54-name environment plus `TF_FLASHNEXT_KV_PAGES=4096`). The v1.2.7 numbers below are kept as the port's history; the r5 cells are `work/DevVsProd/RESULT.md`.` |
| H2 | 12 | "Not for upstream." | The int4 kernel is upstream PR #4183, rebased locally to `984556bf50` on main `7bd7081e0`, with the maintainer's change request being answered (`work/Int4Respond/RESULT.md:5-17`; `gh pr view 4183` shows it OPEN) | CONTRADICTS | `For upstream as PR #4183 (the int4 W4A16 kernel); the build-time routing constants this package uses are local to this campaign and are not part of that PR.` |
| H3 | 145-155 | "on prose most of it is the engine" (the checkpoint and engine shares of the gap) | The decomposition is now known: on the same checkpoint our prose gap is the drafting volume, and the shared per-draft gate was the binder (decision 2; `work/ProseDraft/RESULT.md:9-12,229-240`); `work/SpeedAudit/CORRECTIONS.md:5-22` also retires the old share arithmetic for the one-stream cell | STALE-STATUS | `on prose the larger share was the engine in this window; the 2026-11-23 window then placed the prose gap on the hard-coded shared per-draft gate (`work/ProseDraft/RESULT.md`), and `work/SpeedAudit/CORRECTIONS.md` supersedes the one-stream cell of this decomposition.` |
| H4 | 279-284 | "What remains ... at eight streams on prose about a third of it is rounds (6% more than production) and the rest the round, whose engine-owned cost the kernel log places in the dense projections and read-outs" | Decision 4: the prose residual is drafting volume left in the drafter, acceptance 0.718 against production's 0.750, and the round time is within half a millisecond (51.1 against 51.5 ms) with 3.01 against 3.28 tokens a round (`work/ProseDraft/RESULT.md:145-152,229-240`); it must not be described as a policy stop or as solved | STALE-STATUS | `What remains at eight streams on prose is drafting volume left in the drafter, not the round: at four streams the round costs 51.1 ms against production's 51.5 while tokens a round read 3.01 against 3.28, with acceptance 0.718 against 0.750 (`work/ProseDraft/RESULT.md`).` |
| H5 | whole file | No record of PR #4183's current state | Decision 7: rebased to `984556bf50` on main `7bd7081e0`, dense wrapper narrowed to BF16, `prompt_down_bf16` coverage and the `int4-contract` dispatch committed, device summary outstanding (`work/Int4Respond/RESULT.md:5-17,31-45`) | MISSING-DECISION | Add a section `## PR #4183, state` with the six commits, the 23-file +2030/-4 diff, the lean pair (165 against 165, 0 new), `tools/pr_check.py` (0 errors, 1 advisory), the two conflicted files and their resolutions, and the sentence `Outstanding: the device summary (one Spark window on the pushed head).` |
| H6 | whole file | No record that our own build failed prompt following | `work/Int4Window/QUALITY-DEFECT.md:1-30`: on both r2 arms the build answers a few-shot example instead of the question (166 of 500 GSM8K replies on FP4, 145 of 500 on INT4 name the jelly-beans example, against 0 and 1 in the 2026-11-19 run); GSM8K falls 96.8 to 8.8 percent (FP4) and 96.4 to 28.6 percent (INT4); verdict `needs a re-run` on a build that reproduces the 2026-11-19 greedy text. The r4 fix to 0008's shared-direct write-back is the prime suspect (`patches/main-1ece6e6db-r5/README.md:21-27`: the same lever produced a 0 of 20 answer set), and no r5 or r5-int4 prompt-following run exists | MISSING-DECISION | Add: `## Quality: an open defect` then `The 2026-11-22 quality window on the r2 tree scored GSM8K at 8.8 percent (FP4) and 28.6 percent (INT4) because the build answered a few-shot example instead of the question (`work/Int4Window/QUALITY-DEFECT.md`). The 0008 shared-direct write-back was the suspect and its r4 fix produces a 20 of 20 answer set, but no r5 or r5-int4 run has re-measured prompt following: treat internal exactness (drafted equals "draft": false) as no evidence here, and re-run the 1,664-item window on the current image before any quality claim.` |

## docs/CATCHUP-1.2.6.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| I1 | 1528-1538 | "the gain we measured on v1.2.7 plus our patches, with fp8 KV and our harness, does not show on main at two and four streams, and on this evidence it is no case for an upstream performance issue" | Decision 2: `TF_FLASHNEXT_SHARED_DRAFTS=0` is measured and promoted, 7 to 11 percent at 2 to 8 streams, 54 percent of the prose gap, exact on every arm (`work/ProseDraft/RESULT.md:9-12,95-98,229-240`); the cause is upstream's hard-coded `shared_stop = 0.6` (`cuda_lanes_draft.zig:26-30`, added 2026-11-10), absent from the production engine | CONTRADICTS | `That 1.2.7 window measured the pair on a different stack (bf16 KV, 131,072, four streams, `GREEDY_WIDE` inactive); on the r5 stack `TF_FLASHNEXT_SHARED_DRAFTS=0` alone is 7 to 11 percent at 2 to 8 streams with exactness on every arm (`work/ProseDraft/RESULT.md`), and the upstream hard-coded `shared_stop = 0.6` is the named cause.` |
| I2 | 1125-1130 | "a looser rule (-0.25, -0.15) loses at every stream count on this checkpoint, so -0.4 stays" | `dev.env:12` carries `TF_FLASHNEXT_CONFIDENCE=-0.15` (as a production launcher value, not a measured lever), and `work/ProseDraft/RESULT.md` measures `CONFIDENCE=-0.20` as +1.3 percent on prose and +2.2 on code at one stream with the shared gate off, while `docs/ZIG-SPEED-CAMPAIGN-2026-10.md:281` records `keep -0.15` | CONFLICT-BETWEEN-DOCS | `a looser rule (-0.25, -0.15) loses at every stream count on the FP4 1.2.7 checkpoint, so -0.4 stays there. Our r5 arm carries production's -0.15 as a launcher value (`dev.env`), and with the shared gate off the confidence arms are level or better (`work/ProseDraft/RESULT.md`).` |
| I3 | 563-566 | "the drafter's contribution is still unmeasured and needs the real switch found before any drafter conclusion is drawn" | The switch was found and named: the hard-coded shared per-draft gate at `cuda_lanes_draft.zig:26-30`, measured in `work/ProseDraft/RESULT.md` and `work/GapArms/RESULT.md` (ours drafts 1.92 tokens a round against production's 3.03 while accepting the same fraction) | STALE-STATUS | `the drafter's contribution is now measured: the shared per-draft gate (`cuda_lanes_draft.zig:26-30`) is the binder, and removing it moves drafted a round from 1.9 to 2.8 at four streams (`work/ProseDraft/RESULT.md`).` |
| I4 | 1334-1350 | "on prose still 5 to 7% more [rounds], and the rest is the round" | Decision 4: the residual is drafting volume (2.8 against 3.03 drafted a round, acceptance 0.718 against 0.750), and the round is within 0.4 ms (51.1 against 51.5) at four streams (`work/ProseDraft/RESULT.md:145-152,229-240`) | STALE-STATUS | `on prose our chain still takes fewer drafts a round than production's (2.8 against 3.03 with the gate off, acceptance 0.718 against 0.750), and the round is level (51.1 against 51.5 ms): the residual is drafting volume, not the round.` |
| I5 | 908 | Names `scripts/qwen38/zig/target/gluechain.sh` as the driver of the glue measurement | No such file exists (`test -e`); the directory holds no `glue*` script and nothing in `work/` holds a copy | STALE-STATUS | `the driver is not carried in this repo; the 2026-11-11 glue measurement was run from spark6 `~/work/target/glue.log` and its script has been removed, so the log is the record.` |
| I6 | 1-5 | The header says "Measured on spark6 on 2026-11-11" but the file is cited by `patches/1.2.6/README.md:11` and `patches/1.2.7/README.md:11` as "every measurement behind the table" with no statement that the stack is superseded | The base has moved twice since (`964174ea05`, `1ece6e6db`), and the current series is `patches/main-1ece6e6db-r5` | MISSING-DECISION | Insert after line 5: `**Historical record.** This file documents the TensorFold v1.2.6 (`6e9af9302`) and v1.2.7 (`93a2e93ec`) series. Both are superseded: the current series is `patches/main-1ece6e6db-r5` on upstream main `1ece6e6db`. The measurements stand for the stack they name; the launcher blocks and setting verdicts in it are not the current arm's.` |
| I7 | 554 (against 380-382) | The knob sweep's row for `WINDOW_GRAPH=0` reads "-29.0% / -30.6% ... graph replay is worth about 40% at one stream and it is already ON" | The same file's round log measures the graph off and finds the forward unchanged (49.2 and 54.4 ms) with the serve at 61.1 / 81.9 against 60.4 / 81.8, and states "The earlier '29% from the graph' came from the invalid sweep" (`docs/CATCHUP-1.2.6.md:380-382`) | CONFLICT-BETWEEN-DOCS | Replace the verdict cell with `inert on the repaired rung: the forward costs 49.2 and 54.4 ms with the graph off and the serve is level, so the earlier 29 to 40 percent came from the invalid sweep (see "Where a round goes")` |
| I8 | 1166-1172 | "`GREEDY_WIDE=8` ... is not yet a shipping recommendation: the rule is no regression at any stream count, so it needs 1, 2 and 4 streams and a golden before it can go into the README" | The 1 and 4 stream cells are measured level: `work/ProseDraft/RESULT.md`'s G8 arm reads prose 70.1 and 207.3, code 97.5 and 276.4, against the baseline's 69.9 and 207.8, 97.2 and 276.8; `dev.env:57-59` records `TF_FLASHNEXT_GREEDY_WIDE=8` as measured level and deliberately not set | STALE-STATUS | `it is level at 1 and 4 streams and +5 to 6 percent on code at 6 and 8 (`work/ProseDraft/RESULT.md`, the G8 arm; `dev.env` footer), so it is a level setting and not a promoted gain: leave it unset and carry the cells.` |
| I9 | 347, 575, 609 | "the plain reader is faster: serve with it off" (0013's `GATHER_READ=0`), "the plain reader is the default" and "kept as the setting" | `patches/1.2.6/README.md:24` records the same lever as "decode level with the base's own readers (61.6 / 81.3 against 62.1 / 81.9)" and lists the switch as `GATHER_READ=pread` (on); the recipe exports `GATHER_READ=pread` (`AGENTS.md:266-270`) and no current doc records which reader the served arm runs | CONFLICT-BETWEEN-DOCS | `the plain reader measured level against the pread row cache on the repaired rung (61.6 / 81.3 against 62.1 / 81.9, `patches/1.2.6/README.md`); the recipe exports `GATHER_READ=pread`, so state the reader the arm actually runs instead of a default.` |

## docs/SPEED-TARGET-1.2.6.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| J1 | 1-7 | The file presents itself as the target document ("This branch is upstream TensorFold v1.2.6 plus this one document") | `production:production/SPEED-TARGET.md` is 108 lines and carries a 2026-11-13 model note that this copy lacks (5 experts a token against our 10, so a cross-checkpoint cell compares a different model configuration); AGENTS.md:12-13 names the production branch's copy as the target. Two copies, one six lines short | CONFLICT-BETWEEN-DOCS | Replace the file with a pointer plus the current copy: `The target is `production/SPEED-TARGET.md` on the `production` branch, read in its worktree (`git worktree add work/prod production`). It is reproduced below for readers of `docs/`, model note included.` and paste the 108-line production copy, or delete the file and leave the pointer. |

## docs/OVERNIGHT-1.2.6.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| K1 | 29-40, 150-165 | "## Open" lists three defects and "## Next steps, in the order they block" lists five items (finish the per-lever split, root-cause the 4 of 6 golden and 0 of 2080 self-check, re-land the pread draft read-ahead, reconcile the per-stream memory estimate, retune the 1.0.0 env) | The 1.2.6 series is retired and the stack has been re-seated three times (`docs/RESEAT-1ece6e6db.md`, `docs/RESTACK-main-964174ea05.md`, `patches/main-1ece6e6db-r5/README.md:1-19`); the self-check reads 1,176 of 2,080 on the current series (`patches/main-1ece6e6db-r5/README.md:17-18`), and the memory estimate was reconciled by the page pool (`work/KvTierShip/RESULT.md:45-65`) | STALE-STATUS | Replace the two sections with one line each: `## Open (at 2026-11-11, closed)` then `Every item here was carried into the 1ece6e6db series: the self-check reads 1,176 of 2,080, the stream estimate is reconciled by `TF_FLASHNEXT_KV_PAGES`, and the pread read-ahead is patch 0004. Nothing in this file is an open work item.` |

## docs/FP4-PORT-AND-RETEST.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| L1 | 41-49 | "## 2. Open risk: none of our engine patches have been measured on FP4" | The FP4 arm has been measured repeatedly since: `patches/1.2.7/README.md`'s FP4 block (2026-11-14), the 19-patch FP4 arm at 1 to 8 streams (`docs/PROD-VS-ZIG-2026-11-18.md:133-144`), and `work/QInt4/RESULT.md`'s r5 FP4 image | STALE-STATUS | `## 2. The FP4 risk, and its resolution` then `Every lever of the series has since been measured on the FP4 checkpoint: the launcher block (``patches/1.2.7/README.md``), the 1 to 8 stream table (``docs/PROD-VS-ZIG-2026-11-18.md``) and the r5 FP4 image (``work/QInt4/RESULT.md``). The risk table below is the 2026-10-25 triage that ordered that work.` |
| L2 | 260, 394 | "The PR texts: `PR_64row.md` (the 48-row receipt) and `PR_48row_stacked.md` (the resync on top), both filled from these runs"; "PR text: fill `upstream/tensorfold-pr-copy-resync/PR_64row.md` from this section" | `upstream/tensorfold-pr-copy-resync/` holds `PR.md`, `PR_48row_stacked.md`, `PR_draft.md`, `PR_final.md`, `PR_final_next.md`, `README_draft.md`, `RECEIPT.md`; there is no `PR_64row.md` anywhere (`test -e`, `find work -name PR_64row.md` empty) | STALE-STATUS | At 260: `The PR texts: `PR_48row_stacked.md` (the resync on top) and `PR_final_next.md`, both filled from these runs.` At 394: `PR text: fill `upstream/tensorfold-pr-copy-resync/PR_final_next.md` from this section.` |
| L3 | 396-400 | "Settings retune on 1.2.4: keep both defaults ... keep `TF_FLASHNEXT_CONFIDENCE=-0.4` and `TF_FLASHNEXT_PRODUCT_STREAMS=5`. `CONFIDENCE=-0.15` costs 9.0% prose and 4.3% code at 1 stream" | `dev.env:12` sets -0.15 and `prod.env:42` sets `TF_FLASHNEXT_PRODUCT_STREAMS=8`; `work/ProseDraft/RESULT.md`'s C20 arm reads -0.20 as +1.3 prose and +2.2 code at one stream, and the drafter table finds -0.15 best on the INT4 checkpoint (`docs/INT4-PORT.md:206-227`) | CONFLICT-BETWEEN-DOCS | `keep `TF_FLASHNEXT_CONFIDENCE=-0.4` and `TF_FLASHNEXT_PRODUCT_STREAMS=5` for the 1.2.4 NVFP4 stack only; production runs 8 product streams and -0.15, and the optimum moves with the checkpoint (``docs/INT4-PORT.md``).` |

## docs/SPEED-CAMPAIGN-2026-10.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| M1 | 4-5 | "The live config and each layer's evidence are in `scripts/qwen38/README.md`" | That README documents this retired serve as history and carries no live config (see C1 to C7); the live config is `scripts/qwen38/zig/target/env/dev.env` and `prod.env` | STALE-STATUS | `The October campaign's live config was `scripts/qwen38/README.md`; today's is `scripts/qwen38/zig/target/env/dev.env` (our arm) and `prod.env` (production).` |
| M2 | 11-16 | The "Status" column reads "production (in `tensorfold-qwen38:v061-ots`)", "production (2026-10-08 ~00:12)", "production (2026-10-08 ~02:01, image 8e4a7bafb67d)" | All seven layers are RETIRED with the Python serve (`scripts/qwen38/README.md:10-11`); nothing from that image serves | CONTRADICTS | Change every "production" in the column to `RETIRED (was production 2026-10-08)` and add one line above the table: `The Python serve and all seven layers were retired on 2026-10-09 when spark4 joined the GLM TP=2 pair; the layer directories remain in the tree as history.` |

## docs/ZIG-SPEED-CAMPAIGN-2026-10.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| N1 | 334-345 | "### Follow-up work (carry to the new engine)" lists five open items (warm turns must yield, 0029, rewind checkpoints, untested leads, the re-test rule) | Nothing from this list is on the current series, which is a different engine and base (`patches/main-1ece6e6db-r5/README.md`); the zmerge8 stack it profiles is the production image and is frozen (`AGENTS.md:9-13`), so these items have no addressee | STALE-STATUS | `### Follow-up work (carried, or closed)` then for each item one clause saying where it went: `warm turns: production runs WARM_TURNS=0 and the trade is recorded in ``qwen6-start.sh``; 0029: dropped; rewind checkpoints: superseded by the NVMe KV tier (``work/KvTierShip``); untested leads: no current owner; the re-test rule is the fleet rule in ``~/.omp/agent/AGENTS.md``. Nothing here is an open item of the current series.` |
| N2 | 293 | "Open: more boots at 32k-128k and the startup estimate at the default 8 streams" (the `PREFILL_ROWS=4096` candidate) | The name and the question are both superseded: the current tree reads `TF_FLASHNEXT_CHUNK` and `CHUNK_SOLO`, measured at 4,096 in `work/GapArms/RESULT.md` (3.6 and 2.5 percent at 8k and 32k over 3,072) and carried in `dev.env:22-27`; the 8-stream estimate is reconciled by the page pool (`work/KvTierShip/RESULT.md:45-65`) | STALE-STATUS | `Closed: the same lever is `TF_FLASHNEXT_CHUNK=4096` on the current tree (3.6 and 2.5 percent at 8k and 32k, `work/GapArms/RESULT.md`), and the 8-stream estimate is reconciled by `TF_FLASHNEXT_KV_PAGES`.` |

## patches/main-1ece6e6db-r5/README.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| O1 | 57 | 0004's upstream path: "PR #4009 `flashnext-gather-early-up` (the gather-early part only), open" | #4009 merged 2026-11-21T21:00:32Z (`gh pr view 4009`); decision 6 lists 0004's gather-early half as absorbed and due for retirement at the next re-seat | STALE-STATUS | `PR #4009 `flashnext-gather-early-up` (the gather-early part only), MERGED (2026-11-21). **Absorbed: retire the gather-early half at the next re-seat onto a base that contains it, keeping the row cache, draft-ahead and the single shared gather.**` |
| O2 | 72 | 0019: "the fused split's kernel contract ... PR #3475 carries the contract in its own shape" | #3475 merged 2026-11-21T23:54:41Z (`gh pr view 3475`); decision 6 names 0019 and its contract as absorbed and due for retirement | MISSING-DECISION | `| 0019 | the fused split's kernel contract | none (a `tf-cuda-test` contract) | PR #3475, MERGED (2026-11-21, `308d5e1fd`) carries the contract in its own shape: **retire 0019 and 0017 at the next re-seat** |` |
| O3 | 92-96 | The recommended launcher block ends "# at 6 and 8 streams with a 262,144 window also `TF_FLASHNEXT_KV_PAGES=4096`; `TF_FLASHNEXT_HC_Q12` stays unset" | Decision 1: no serve setting may be unset; the engine's default written out counts and a note does not. `dev.env` writes every setting it relies on, including the level ones | CONTRADICTS | `# TF_FLASHNEXT_KV_PAGES=4096 at 6 and 8 streams with a 262,144 window, and in every other case TF_FLASHNEXT_KV_PAGES=<the plan's page count>; TF_FLASHNEXT_HC_Q12=0 (measured level, kept off explicitly). Every setting the block relies on is written, per the env rule in AGENTS.md.` |

## patches/1.2.6/README.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| P1 | 38-41 | "The other stock knobs tried on the unpatched binary (`DRAFTS_GREEDY`, `PLE_IO=mmap`, `TABLE_WARM`, `SHARED_DRAFTS`, ...) move nothing or lose" | `TF_FLASHNEXT_SHARED_DRAFTS=0` is promoted: 7 to 11 percent at 2 to 8 streams, 54 percent of the prose gap, exact on every arm (`work/ProseDraft/RESULT.md:9-12,95-98`; `dev.env:43-49`) | CONTRADICTS | `The other stock knobs tried on the unpatched binary (`DRAFTS_GREEDY`, `PLE_IO=mmap`, `TABLE_WARM`, `KEEP_INPASS`, ...) move nothing or lose, except `TF_FLASHNEXT_SHARED_DRAFTS=0`, which was measured later on the r5 stack and promoted (7 to 11 percent at 2 to 8 streams, `work/ProseDraft/RESULT.md`).` |
| P2 | 1-13 | The package presents itself as the series, with one RETIRED note about the 32-patch series, and never says this 13-patch series is superseded | The base has moved from v1.2.6 to v1.2.7, `964174ea05` and `1ece6e6db`; the current series is `patches/main-1ece6e6db-r5` (`docs/RESEAT-1ece6e6db.md`, `docs/RESTACK-main-964174ea05.md`) | STALE-STATUS | Insert after line 1: `**Historical package.** This series was cut against v1.2.6 and is superseded by `patches/1.2.7`, `patches/main-964174ea05` and, today, `patches/main-1ece6e6db-r5`. Its measurements stand for the base it names.` |

## patches/1.2.7/README.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| Q1 | 1-15 | Same shape as P2: the file presents the 19-patch v1.2.7 series as the series, with no superseded note, and its rows still give #3477, #3727, #3475 and #4009 as open | All four merged on 2026-11-20 and 2026-11-21 (`gh pr view`; decision 6); the current series is `patches/main-1ece6e6db-r5` | STALE-STATUS | Insert after line 1: `**Historical package.** Cut against v1.2.7 (`93a2e93ec`), superseded by `patches/main-964174ea05` and `patches/main-1ece6e6db-r5`. The PRs its table names as open have since merged: #3727 (2026-11-20), #3477, #4009 and #3475 (2026-11-21).` |

## patches/main-1ece6e6db-r5-int4/README.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| R1 | 1, 26 | "(experimental, not the accepted series)" and "STATUS: host gates only, and every one of them green on the re-cut patches" | The tree has since been built into `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` and served at production's shape for five stream counts (`work/DevVsProd/RESULT.md:12-27`), gated internally (`work/QInt4/RESULT.md:9-11,36-45`), and its kernel is the subject of PR #4183 (`work/Int4Respond/RESULT.md:5-17`) | STALE-STATUS | `**STATUS: host gates green, built and served.** Image `tensorfold-qwen38:qr-b-r5int4-1ece6e6d`, served at production's shape (`work/DevVsProd/RESULT.md`), internal exactness 20 of 20 (`work/QInt4/RESULT.md`). It is still the experimental arm: the accepted series is r5 alone. Prompt-following has NOT been re-measured on this tree (`work/Int4Window/QUALITY-DEFECT.md`).` |

## docs/RESEAT-1ece6e6db.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| S1 | 24-25 | "The lever PRs are still open: #4009 (gather early), #4075 (copy window), #3477 (draft head), #3727 (vision), #3218 (mxfp8), #3475 (fused split), #3523 (config widths), #4183 (INT4)" | #4009, #3477, #3475, #3727 and #3413 merged on 2026-11-20 and 2026-11-21 (`gh pr view`; decision 5); #4075 is clean awaiting their GB10 check; #3218 and #3523 await device checks; #4183 answers a maintainer request (`work/Int4Respond`) | CONTRADICTS | `The lever PRs at this study's date: #4009, #3477, #3475 and #3727 have since MERGED (2026-11-20 to 2026-11-21) and are due for retirement at the next re-seat; #4075 is clean and awaiting upstream's GB10 check; #3218 and #3523 await upstream device checks; #4183 answers a maintainer change request. Issue #4107 is another contributor's fp8 KV.` |
| S2 | 64 | "`TF_FLASHNEXT_DRAFT_HEAD` exists only as the environment read (#3477 not merged) and `default_mode` is absent" | #3477 merged 2026-11-21T09:32:48Z (`gh pr view 3477`; `patches/main-1ece6e6db-r5/README.md:60`) | STALE-STATUS | ``TF_FLASHNEXT_DRAFT_HEAD` was an environment read only at this date; #3477 merged on 2026-11-21 (`230837886`) and supersedes 0007 on any base that contains it.` |
| S3 | 46-48 | "No patch is wholly retired. The two partially absorbed ones are recorded in `patches/main-1ece6e6db/RETIRED.md`" | Decision 6: five units are absorbed and must be retired at the next re-seat (0007 #3477, 0017 and 0019 #3475, 0011 #3727, 0004's gather-early half #4009); the r5 README already notes four of them | MISSING-DECISION | Replace with: `No patch was wholly retired at this re-seat. Since then five units are absorbed and must be retired at the next re-seat: 0007 (#3477, `230837886`), 0011 (#3727, `174cfff34`), 0017 and its contract 0019 (#3475, `308d5e1fd`), and 0004's gather-early half (#4009, `69e4d0f04`). `patches/main-1ece6e6db-r5/RETIRED.md` carries the hunk-level record.` |

## docs/RESEAT-d7c969c64.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| T1 | 38-55 | The per-patch table reads "PR #3726 OPEN", "PR #3477 OPEN", "PR #3413 OPEN", "PR #3727 OPEN", "PR #3218 OPEN", "PR #3475 OPEN", and line 55 "they are all OPEN with `mergedAt` null" | #3726, #3413, #3477, #3727 and #3475 all merged on 2026-11-19 to 2026-11-21 (`gh pr view`; `docs/RESEAT-1ece6e6db.md:19-22`) | STALE-STATUS | Insert after line 2: `**Historical classification (2026-11-19).** The PR states in the tables below were read at this date; #3726, #3413, #3477, #3727 and #3475 have since merged. Use the retirement worklist in `docs/RESEAT-1ece6e6db.md` and `patches/main-1ece6e6db-r5/RETIRED.md` for the current disposition.` |

## docs/RESTACK-main-964174ea05.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| U1 | 47-49 | "none retired - upstream absorbed none of them. The four that are pending upstream rather than absent are 0014 (PR #3218, OPEN), 0008 (PR #3413, OPEN), 0007 (issue to be filed) and 0017 + 0019 (to be filed)" | Five units have since been absorbed: #3413 (2026-11-20), #3727 (2026-11-20), #3477 (2026-11-21), #3475 (2026-11-21) and #4009 (2026-11-21) (`gh pr view`; decision 6; `patches/main-1ece6e6db-r5/README.md:54-72`) | STALE-STATUS | `the re-seat retired nothing; since then five units are absorbed and go at the next re-seat (#3477 for 0007, #3727 for 0011, #3475 for 0017 and 0019, #4009 for 0004's gather-early half). #3218 remains open awaiting upstream's device check.` |
| U2 | 96-131 | "0004 keep or retire: A/B on spark6 ... Verdict: 0004 stays (re-seated)" | Decision 6: 0004's gather-early half is absorbed upstream (#4009, merged 2026-11-21) and must be retired at the next re-seat; the row cache, draft-ahead and single shared gather stay. This A/B measured the whole patch on the old base | STALE-STATUS | Append: `Superseded in part (2026-11-21): #4009 merged the gather-early half (`69e4d0f04`), so the next re-seat retires that half and re-tests the row cache, draft-ahead and the single gather on the new base; this verdict covers the patch as it was cut.` |

## docs/QUALITY-A-VS-B-2026-11-18.md

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| V1 | 1-3 | "Quality: INT4-AutoRound against FP4-Local, one window (spark6, 2026-11-19)" and "STATUS: measured 2026-11-19 ... production was restored and answers `/health` 200" | Everything the header claims about that window holds. What it lacks is the state of our OWN build: `work/Int4Window/QUALITY-DEFECT.md` measured both r2 arms failing prompt following (GSM8K 8.8 and 28.6 percent), so a reader of the only quality doc would carry "the checkpoints are indistinguishable" onto a build that was never re-measured for it | MISSING-DECISION | Insert after line 4: `**Superseded in one respect (2026-11-22).** This window compares production's serve against the recipe's Zig serve. A later window on OUR series (r2) found the build answering a few-shot example instead of the question, GSM8K 8.8 percent (FP4) and 28.6 percent (INT4), and ruled that window not salvageable (`work/Int4Window/QUALITY-DEFECT.md`). Nothing here is evidence about our series' prompt following; that is unmeasured on r5.` |

## scripts/patch-packages.list

| # | line | claim as written | current truth and source | verdict | exact replacement text |
|---|---|---|---|---|---|
| W1 | 1 | "# Roots the gate walks for patch packages (depth 2). One directory per line." | `scripts/check-patch-packages.sh:63` walks `find "$root" -maxdepth 3`, and AGENTS.md:244 says depth 3; the gate reports `CLEAN (16 package dirs checked, 1 grandfathered)` | STALE-NUMBER | `# Roots the gate walks for patch packages (depth 3). One directory per line.` |

---

# Cross-document rule conflicts

Eleven places where two documents state different rules or different facts and a reader must be told which wins. Each
row names both sides.

| # | the conflict | both sides | which side is current, and the fix |
|---|---|---|---|
| X1 | Where the serve runs | `AGENTS.md:3,18` and `README.md:3,10-13` say spark4 with the Python engine; `scripts/qwen38/README.md:3,10` says spark6 since 2026-11-07 and calls the spark4 serve RETIRED | spark6. Fix A1, A2, B1, B2, C1 |
| X2 | What the SSOT is | `AGENTS.md:19-20` designates `scripts/qwen38/README.md` as the SSOT for the serve; `AGENTS.md:245-256` (the Gate) and `dev.env` make the env the record and require every setting to be written there; the SSOT names none of the 14 settings | both rules are current and they are not in conflict in principle, only in fact: the SSOT must point at the env and the packages, and the env gate stays. Fix A3, C5 |
| X3 | The prose gap's cause | Decision 2 and `dev.env:43-49` with `work/ProseDraft/RESULT.md` say the hard-coded `shared_stop = 0.6` is the binder, worth 7 to 11 percent and 54 percent of the gap; `patches/1.2.6/README.md:38-41` says `SHARED_DRAFTS` "moves nothing or loses"; `docs/CATCHUP-1.2.6.md:1528-1538` says it "is no case for an upstream performance issue"; `docs/INT4-PORT.md:145-155,279-284` puts the residual on the engine and the round | ProseDraft (the newest, exactness-checked window). Fix P1, I1, H3, H4 |
| X4 | The checkpoint route | `docs/PARITY-CAMPAIGN-1.2.4.md:55-64,86` says "NVFP4, no INT4 port"; `patches/main-1ece6e6db-r5-int4/README.md`, `work/DevVsProd/RESULT.md` and `dev.env`'s INT4 arm say the INT4 port exists and serves production's checkpoint | the INT4 port (2026-11-13 onward). Fix G2, G3 |
| X5 | The confidence value | `docs/CATCHUP-1.2.6.md:1125-1130` says "a looser rule (-0.25, -0.15) loses at every stream count ... so -0.4 stays"; `docs/FP4-PORT-AND-RETEST.md:396-400` says "keep both defaults ... -0.15 costs 9.0% prose and 4.3% code"; `dev.env:12` sets `-0.15`; `docs/ZIG-SPEED-CAMPAIGN-2026-10.md:281` says "keep -0.15"; `work/ProseDraft/RESULT.md` measures -0.20 as +1.3 and +2.2 percent at one stream with the gate off | both are true of different stacks: -0.4 on the NVFP4 1.2.4/1.2.7 stacks, -0.15 as production's launcher value on the INT4 r5 arm. Fix I2, L3 |
| X6 | How many settings production's launcher exports | `scripts/qwen38/zig/target/env/prod.env:1` says "the 52 settings" (and the file has 52 exports, copied 2026-11-20); `docs/PROD-VS-ZIG-2026-11-18.md:57` says "its own 52 settings"; `work/ProseDraft/RESULT.md:56` says "production's 54 names"; `work/KvTierShip/RESULT.md:9` says "production's own 54-variable environment (source: the running container)" | the 2026-11-23 records read the live container, so the launcher has grown to 54 and `prod.env`, copied on 2026-11-20, is two settings behind the live launcher. Re-copy `prod.env` from the container and date the copy; no doc change needed beyond the header |
| X7 | Which target document is the target | `AGENTS.md:12-13` names `production/SPEED-TARGET.md`; `docs/SPEED-TARGET-1.2.6.md` is a 102-line copy without the 2026-11-13 model note, and `docs/` presents it as a document in its own right | the production branch's copy (108 lines, model note included). Fix J1 |
| X8 | Decision 1 (no unset setting) against the recommended blocks | Decision 1 and `AGENTS.md:245-256` fail a setting with no value; `patches/main-1ece6e6db-r5/README.md:96` writes "`TF_FLASHNEXT_HC_Q12` stays unset"; `docs/CATCHUP-1.2.6.md:1486-1492` gives a two-line block that sets six names and leaves the rest to the recipe | decision 1. Fix O3, and rewrite any other launcher block that relies on absence |
| X9 | References to the retired repository against the banner that retires it | `docs/OVERLAP-1.2.6.md:3`, `docs/PARITY-CAMPAIGN-1.2.4.md:3` and `docs/FP4-PORT-AND-RETEST.md:3` each carry a RETIRED REFERENCE banner, and each body then points a reader at `ots/tensorfold-levers124` as if it existed (OVERLAP 9-11 and 52-63, PARITY 7-11, FP4 173, 215, 293, 325, 375) | the banner. Fix F2, F3, G1, and treat FP4's mentions as historical labels (they name backup branches, which is the right use) |
| X10 | The gate's walk depth | `AGENTS.md:244` says depth 3; `scripts/patch-packages.list:1` says depth 2; the script uses `-maxdepth 3` | the script and AGENTS.md. Fix W1 |
| X11 | Which levers are still live | Decision 6 names five absorbed units (0007, 0017, 0019, 0011, 0004's half); `patches/main-1ece6e6db-r5/README.md:57` says #4009 is open and its 0019 row carries no retirement note; `docs/RESEAT-1ece6e6db.md:24-25` and `docs/RESEAT-d7c969c64.md:38-55` still list the merged PRs as open | decision 6. Fix O1, O2, S1, S2, S3, T1, U1, U2, Q1 |
| X12 | Which n-gram reader the arm runs | `docs/CATCHUP-1.2.6.md:575,609` says the plain reader is faster and "is the default"; `patches/1.2.6/README.md:24` calls the lever level and names `GATHER_READ=pread` as the switch; `AGENTS.md:266-270` says the recipe exports `GATHER_READ=pread`, and no doc records the served arm's reader | the measurement says level (1.2.6 package), so the choice is open and must be written down, not defaulted. Fix I9 |

---

# The named checks, answered

| check | answer |
|---|---|
| Any doc that states the prose gap is an engine difference | Yes, three: `docs/INT4-PORT.md:154` ("on prose most of it is the engine"), `docs/CATCHUP-1.2.6.md:105` ("per-round cost, which is the engine") and `docs/CATCHUP-1.2.6.md:1339-1341` ("the rest is the engine"). `docs/PROD-VS-ZIG-2026-11-18.md:222-229` puts the residual "in the rounds", which is a dated window's own reading and is superseded by ProseDraft. Rows H3, I1, I4 |
| Any doc listing settings as "not yet measured" that the decisions now measure | Yes: `docs/CATCHUP-1.2.6.md:563-566` ("the drafter's contribution is still unmeasured and needs the real switch found"), `docs/FP4-PORT-AND-RETEST.md:41-49` ("none of our engine patches have been measured on FP4"), and `docs/FP4-PORT-AND-RETEST.md:51,210` ("unproven there", "unmeasured"), and `docs/CATCHUP-1.2.6.md:1166-1172` (the greedy width needs 1, 2 and 4 streams) with `docs/ZIG-SPEED-CAMPAIGN-2026-10.md:293` (more boots at the default 8 streams). Rows I3, I8, L1, N2. `dev.env`'s footer ("NOT re-measured on this stack: TF_FLASHNEXT_MTP_WEIGHTS=mxfp8") is the env's own statement and is not contradicted by any decision |
| Any doc asserting the tier is absent or unproven | None asserts absence. The tier is absent from EVERY doc: no file under `docs/`, no line of `AGENTS.md`, and no line of `scripts/qwen38/README.md` mentions the NVMe KV tier, `--prompt-cache-disk`, `--learn-conversations` or `TF_FLASHNEXT_KV_PAGES`. Only `dev.env:31-42` records it. That is a MISSING-DECISION rather than a CONTRADICTS: row C6 |
| Any doc naming a retired lever as active without the retirement note | Yes: `patches/main-1ece6e6db-r5/README.md:57` (#4009 open) and its 0019 row (`:72`); `patches/1.2.6/README.md` (no superseded note, and `SHARED_DRAFTS` among the losses at `:38-41`); `patches/1.2.7/README.md` (no superseded note); `docs/RESEAT-1ece6e6db.md:24-25,64`; `docs/RESEAT-d7c969c64.md:38-55`; `docs/RESTACK-main-964174ea05.md:49`. Rows O1, O2, P1, P2, Q1, S1, S2, T1, U1 |
| `OPEN-PR-COVERAGE.md` against the upstream list | Contradicts it entirely: no merged PR of ours, no #4075, #3218, #3523, #4183 or #4449, and a verdict that no open PR covers our work. `gh pr view` confirms the decision list exactly. Rows D1 to D4 |
| `scripts/qwen38/README.md` against `dev.env` | No overlap. `dev.env` sets 14 settings; the SSOT describes none of them and names neither env file. The SSOT's own settings (MTP_DRAFTS, TENSORFOLD_CHAIN_RULE, TENSORFOLD_CHAIN_T, TF_PLE_*, TENSORFOLD_MTP_GRAPHS, TENSORFOLD_PLE_DEFER, TENSORFOLD_PLE_NATIVE) belong to the retired Python engine. Rows C5, C6, C7 |
| AGENTS.md's gate list against the scripts that exist | All four exist and behave as described: `scripts/check-patch-packages.sh` (ran, CLEAN, 16 packages, 1 grandfathered), `scripts/check-python.sh`, `scripts/qwen38/zig/target/env/check-env-coverage.py` (has `--table`, `--dev`, `--register`, `--scopes`, `--carried-pattern`, `--strict-carried`), `scripts/check-patch-reverts.py` (`SERIES_DIR [--allow FILE]`, as documented). The Gate text itself is an uncommitted working-tree change and should be committed; see the state note above |
| Any doc telling a reader to run or read a path that does not exist | Two, both ours: `docs/CATCHUP-1.2.6.md:908` names `scripts/qwen38/zig/target/gluechain.sh` (absent); `docs/FP4-PORT-AND-RETEST.md:260,394` names `upstream/tensorfold-pr-copy-resync/PR_64row.md` (absent). Every other missing path belongs to another repo (ots-infra, glm5.3-flash-dev, the recipe) or to upstream TensorFold. Rows I5, L2 |

---

# What must move before a historical file is deleted

`work/DocAudit/CURRENT-DOCS.md` (Main, 2026-11-23) records the owner rule that superseded material is removed rather
than annotated. The brief for this audit asks only that a dated record's header say so, so the rows above propose
headers; where the owner deletes instead, this table is the transfer list. Each row names the one thing in that file
that no kept file states.

| file | what must move first | destination |
|---|---|---|
| `docs/RESEAT-1ece6e6db.md` | the retirement worklist of decision 6 (0007 #3477, 0011 #3727, 0017 and 0019 #3475, 0004's gather-early half #4009), with the landing shas | `patches/main-1ece6e6db-r5/RETIRED.md` and the PR table in `docs/OPEN-PR-COVERAGE.md` |
| `docs/QUALITY-A-VS-B-2026-11-18.md` | the one-paragraph state of our own build: r2 failed prompt following, GSM8K 8.8 and 28.6 percent, r5 unmeasured | `docs/INT4-PORT.md` (row H6) and the SSOT |
| `docs/RESTACK-main-964174ea05.md` | the `TF_PROMPT_INTERMEDIATE` lead (a bounded ladder of intermediate prompt checkpoints, off by default, a lead for long agent turns) and the note that 0004 is not absorbed | the r5 `README.md` follow-up line and `RECORD.md` |
| `docs/OVERLAP-1.2.6.md` | the v1.2.6 window caps (`max_rows` 32, `round_rows` 64, `MAXR` 16) and the statement that the 48-row result applies at that cap | `patches/main-1ece6e6db-r5/README.md`, 0001's row |
| `docs/CATCHUP-1.2.6.md` | nothing: the knob verdicts it corrects are superseded by `dev.env` and `work/ProseDraft/RESULT.md`, and its measurements are cited by the 1.2.6 and 1.2.7 packages, which keep them | n/a |
| `docs/PARITY-CAMPAIGN-1.2.4.md` | nothing current: its checkpoint decision is reversed (row G2) and must not be carried forward | n/a |
| `docs/RESEAT-d7c969c64.md` | nothing current: the per-patch upstream map is superseded by `patches/main-1ece6e6db-r5/README.md` | n/a |
| `docs/FP4-PORT-AND-RETEST.md` | the 2x2 CONFIDENCE result (the optimum is checkpoint dependent) if `docs/INT4-PORT.md` is also removed | `dev.env`'s comment above `TF_FLASHNEXT_CONFIDENCE`, which already says the value is production's rather than a measured lever |
| `docs/SPEED-CAMPAIGN-2026-10.md`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`, `docs/OVERNIGHT-1.2.6.md` | nothing current | n/a |
| `docs/PROD-VS-ZIG-2026-11-18.md` | nothing: its numbers are cited from `work/` records and its prose-gap reading is superseded | n/a |
| `docs/SPEED-TARGET-1.2.6.md` | do not delete: replace with the `production/SPEED-TARGET.md` copy (row J1) | stays |

---

# Notes and limits

- Five files are dated records whose headers say so and which need no body edit under the brief's historical rule:
  `docs/GB10-THERMAL-BENCHMARK-METHODOLOGY.md` (measured 2026-10-24), `docs/AFFINE3-TILE-MISPICK-2026-11-06.md`
  (found 2026-11-06), `docs/PROD-VS-ZIG-2026-11-18.md` and `docs/QUALITY-A-VS-B-2026-11-18.md` (one window each,
  dates in the title), and `docs/UPSTREAM-WATCHLIST.md` (sectioned by date). `QUALITY-A-VS-B` still gets row V1
  because a dated header cannot carry a fact about OUR build that did not exist when it was written.
- `docs/OVERNIGHT-1.2.6.md`, `docs/INT4-PORT.md`, `docs/CATCHUP-1.2.6.md` and `docs/RESEAT-1ece6e6db.md` also
  carry dates, but each is cited by a package README as the current evidence or the current disposition, so their
  current-state lines were audited.
- Nothing in this audit depends on a tool I did not run: every "missing" is a `test -e`, every PR state is a
  `gh pr view`, every count is a `grep -c` or `wc -l`, and every number quoted from a measurement record carries the
  file and line it came from.
- The single highest-value follow-up outside this report is not a doc edit: no quality measurement exists of the r5
  or r5-int4 build's prompt following, and the only such measurement of our own series failed. That belongs in
  `docs/` as row H6 says, but the fix is a re-run of the 1,664-item window.
