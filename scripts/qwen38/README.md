# scripts/qwen38 - the Qwen3.8 Flash Next serve

**Live: the Zig serve on spark6 `:8888`.** Production is started by the box's `~/qwen6-start-prod.sh` (recipe
`~/qwen-zig-prod`, production's 54-name environment and its `TF_FLASHNEXT_MTP_FP8` overlay); that file is not in this
repo and no change here touches it. The repo's dev launcher is `zig/qwen6-start.sh` (box copy `~/qwen6-start.sh`): the
same image and the same serve - image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, INT4-AutoRound, fp8 KV, 8
streams at a 262,144-token window, thinking on by default (`chat_template_kwargs.enable_thinking=false` turns it
off) - plus the dev engine's defaults: `CHECKPOINT=int4`, `VISION=0`, `KV_DTYPE=fp8`,
`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`, and the persistent KV tier (`--prompt-cache-gib 6 --prompt-cache-disk /cache/kv
--learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20`), each overridable (`LEARN=0` turns the tier off,
`MTP_WEIGHTS=bf16` puts the drafter back on the checkpoint's rows). Boot 83 to 90 s at one to eight streams
(`docs/SPEED-TARGET-1.2.6.md`); golden 6/6 identical to stock on the first boot. It holds the box's GPU lock while it
runs, and spark6 has no passwordless sudo, so arms bind to 127.0.0.1 and production is restored from its own launcher.
`scripts/qwen38/qwen-start.sh` is the RETIRED spark4 Python serve's launcher (image `v061-ots`, TensorFold v0.6.1,
recipe `4c0dea8`) and cannot carry those defaults: that recipe has no `CHECKPOINT` setting, its engine's `--kv-dtype`
is `bf16|int8|int4` only and it has no `--learn-*` or `--prompt-cache-disk` flag, and nothing there reads
`TF_FLASHNEXT_MTP_WEIGHTS`. The launcher table under "Build and boot tools" says which file carries what.

## Our arm (`main`)

- **Series.** The dev engine is `patches/main-1ece6e6db-r5-dev`: one directory of 40 patches on upstream main
  `1ece6e6db`, the r5 core levers (0001 to 0020), the INT4-AutoRound port and its serving pins (0021, 0022), the NVMe
  KV tier with the pool's cache refusal and the whole-ask budget (0023 to 0026), the bf16 draft-head fix (0027, 0028),
  the int4 contract suite with the tolerance branch's three commits (0029 to 0032), the merged serving pins (0033),
  the composed-gate corrections (0034 to 0036), and the green-up fixes for the int4 fixtures, the regenerated
  serving pins and the CLI fixture mode (0037 to 0040).
- **The dev arm is proved.** Image `tensorfold-qwen38:r5dev40` (`sha256:adc40fe3ea7b...`, 459 s build) from these
  40 patches boots at 8 x 262144 with fp8 KV: window self-check 1176 of 1176, five exactness cells EQ with 404
  drafts, `SUMMARY int4: 8 kernels, 8 pass gates 1-4, 0 fail, 0 known findings; 5 controls: 5 red as planted`,
  the tier budget equal to the 6 GiB ask, and a 129k conversation resuming in 0.176 s against 52.487 s cold with
  both its states surviving under that budget. Receipts: `docs/receipts/DevBootComp/`. The dev launcher passes no
  `--dashboard`, so `/stats` is 404 on this boot and the tier numbers come from its own log lines.
  Build gotcha: BuildKit served a cached fetch keyed to the command string's ref, so build with a unique ref per
  attempt or the tree starts from another lane's base.
  Build: `zig/target/build_patches.sh TAG git://192.168.99.16/up-pr/tf 1ece6e6db patches/main-1ece6e6db-r5-dev`.
  `patches/main-1ece6e6db-r5` (the twenty core levers), `patches/main-1ece6e6db-r5-int4`,
  `patches/main-1ece6e6db-r5-kvtier`, `patches/main-1ece6e6db-r5-kvtier-pool`,
  `patches/main-1ece6e6db-r5-int4-kvtier` and `patches/main-1ece6e6db-r5-drafthead-bf16` stay as provenance and as
  alternatives an arm can choose; they are not the dev stack, and a new beneficial patch lands by joining the
  composition. The draft-head pair fixes the series' one serving defect: with `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`
  set, `TF_FLASHNEXT_DRAFT_HEAD=bf16` failed every request with `error (FormatMismatch)` because the drafter's recode
  window covered the draft head's rows. Stock for a series A/B is upstream main at the base built with no patches;
  the last full A/B of the series is `patches/main-964174ea05/README.md`.
- **At production's shape** (8 x 262,144, fp8 KV, production's 54 names plus the page pool) the INT4 arm reads 0.79 of
  production on prose and 0.95 on code at eight streams, level on code at one, two and four; cold prefill is level at 1k
  and 19 to 22 percent behind at 8k and 32k (`docs/receipts/DevVsProd/RESULT.md`).
- **Quality: the r2 prompt-following defect does not reproduce on r5.** The 2026-11-22 window on the r2 tree
  scored GSM8K at 8.8 percent (FP4) and 28.6 percent (INT4) because the build answered a few-shot example instead
  of the question. Measured on 2026-11-23 over all 1,664 items on both r5 arms: echo 1 of 500 each, GSM8K 96.8
  percent on both, MMLU-Pro 75.2 and 75.1, HumanEval 87.2 and 82.3, recitation 82.5 and 82.0, and r5 FP4 is
  byte-identical to the 2026-11-19 FP4 build on all 1,664 replies, so the r4 fix closed it
  (`docs/receipts/EnvBoot/RESULT.md`, and `docs/INT4-PORT.md` has the table).

## The environment

`zig/target/env/dev.env` is the arm's environment of record. `prod.env` is the PRODUCTION engine's complete record:
118 rows, one for every name the production engine reads, each at its value with a verdict and a citation. The
engine is the tree the zmerge8-kfix image was built from (source tar sha256
`e5139fcd8c6101c776d9c600021228d389e648f58a398842498d95c3ebcccecc`, the image's `ai-engine.src-sha256` label),
and it has no `zig/src/platform/environment.zig`: its table is derived from its own read sites and kept at
`docs/receipts/ProdEnvAudit/prod-settings-table.zig` (the served binary's 116 names plus the vision helper's
`TENSORFOLD_VIDEO_TOKENS` and `TENSORFOLD_VISION_WEIGHTS`). Section 1 of prod.env is the 54-name live launcher
environment; section 2 states every other name at the engine's own default, with the read site cited above its line;
the verdicts are the `# prod <kind> NAME:` block in `register.env`. Gates:
`check-env-coverage.py --table docs/receipts/ProdEnvAudit/prod-settings-table.zig --dev prod.env --register
register.env --scopes flashnext,cuda,common --passes '^(TENSORFOLD|TF_FLASHNEXT)_' --tag prod` reads `coverage: 118
settings in scope, set 118, missing 0, absent 17, annotations 118, worklist markers 0, passage-lost 0`, and
`docs/receipts/ProdEnvAudit/check-prod-rows.py` reads `prod-env: 0 setting(s) without a citation` with `citations:
118/118 resolve`; `check-prod-env.py` compares the rows whose `prod` verdict says the container carries them (54) and
stays green. The provenance and every output are in `docs/receipts/ProdEnvAudit/RESULT.md`.

The dev rule (`docs/ENV-REGISTER.md`): **every setting the served
tree reads is SET in `dev.env`**, because presence is what an upstream rebase silently inherits and a value in the
engine's source is invisible to a name-level sweep. The file writes the measured settings below with the record that
proved each one, then every remaining setting the served tree reads at its own read site's default with that read
site quoted; a value that is not the engine default belongs in the measured list with its cells.
The setting-by-setting verdicts and the ranked worklist are in `docs/KNOB-COVERAGE.md`.
`zig/target/env/check-dev-env.py` fails on a missing setting, on a value carried only by a note in `register.env`, and
on a worklist line; `update-env-register.py --defaults-from-tree` builds the worklist.

The composition `patches/main-1ece6e6db-r5-dev` adds four rows to that table (99 in scope rather than 95), and all four
are now stated in `dev.env`: `TF_FLASHNEXT_HEAD_ROW_TILES=2` and `TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1` at production's
served values (read at `zig/src/families/flashnext/cuda_int4.zig:274`/`:432` and `:272`/`:420-421`; every exactness cell
was taken with them - `docs/receipts/QInt4/RESULT.md`, `docs/INT4-PORT.md`), and `TF_FLASHNEXT_INT4_TILE=16` and
`TF_FLASHNEXT_INT4_PROMPT_DOWN=1` at the engine's own defaults (`cuda_int4.zig:151-152` and `:386-387`), both still
unmeasured here. The register's two old `retired` marks for the first pair were wrong - 0021 gives both a reader - and
are now `measured`. On the applied composition the gate reads `coverage: 99 settings in scope, set 99, missing 0,
absent 2, annotations 6, worklist markers 0, passage-lost off` against `~/work/DevEnvComp/tree` (the capture and
its read sites: `work/DevEnvComp/READERS.md`), and
`check-dev-env.py` reads `dev-env: 0 setting(s) without a citation`.

| setting | value | measured or carried | record |
|---|---|---|---|
| `TF_FLASHNEXT_PROMPT_SHARED_DIRECT` | `1` | +1.2 percent at 8k and +1.0 at 32k cold prefill, decode level | `docs/receipts/SDFix/RESULT.md`, `docs/receipts/PatchBisect/RESULT.md` |
| `TF_FLASHNEXT_READOUT_FUSED` | `1` | +3.19 to +6.47 percent cold TTFT, decode level, tokens equal | `docs/receipts/KnobTest/receipt/w1`, `docs/receipts/RoGpu/receipt/cold.md` |
| `TF_FLASHNEXT_CHUNK_SOLO` | `16384` | +1.12 to +1.39 percent at 32k and 64k, 2k and 8k level | `docs/receipts/KnobTest/VERDICTS.md` |
| `TF_FLASHNEXT_CHUNK` | `4096` | +3.6 to +4.1 percent cold TTFT at 1k, 8k and 32k | `docs/receipts/GapArms/RESULT.md` |
| `TF_FLASHNEXT_WINDOW_CHECK` | `1` | +26 and +12 percent on verbatim and one-word copy turns, fail-closed at 32 rows | `docs/receipts/upsubmit/PrCopyWindow/pr-body-g.md` |
| `TF_FLASHNEXT_KV_PAGES` | `4096` | the shape needs it (39.90 GiB against 31.00 without it) and it is the tier's page pool | `docs/receipts/KvTierShip/RESULT.md` |
| `TF_FLASHNEXT_SHARED_DRAFTS` | `0` | +7 to +11 percent at 2 to 8 streams; prose 229.0 against 207.8 tokens a second at four | `docs/receipts/ProseDraft/RESULT.md` |
| `TF_FLASHNEXT_CONFIDENCE` | `-0.15` | production's launcher value, not a measured lever on this tree (-0.20 is level on prose); the FP4 1.2.7 stack's own optimum was -0.4 (`patches/1.2.7/README.md`), so the value is checkpoint-specific | `docs/receipts/ProseDraft/RESULT.md`, `docs/receipts/ProseDraft/POLICY.md` |
| `TF_FLASHNEXT_BATCH_DRAWS`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_WINDOW`, `TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_NO_UPDATE_CHECK`, `TENSORFOLD_VIDEO_TOKENS` | `1`, `15`, `64`, `10`, `1`, `16384` | production's launcher values carried unchanged; `DEPTH` and `WINDOW` have no reader in this tree | `docs/receipts/ProseDraft/POLICY.md` |
| `TF_FLASHNEXT_HEAD_ROW_TILES`, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP` | `2`, `1` | production's launcher values carried; every exactness cell ran with them (32-row head items past 16 rows, `int4_prompt_kernel` for the routed gate/up) | `docs/receipts/QInt4/RESULT.md`, `docs/INT4-PORT.md` |
| `TF_FLASHNEXT_INT4_TILE`, `TF_FLASHNEXT_INT4_PROMPT_DOWN` | `16`, `1` | the engine's own defaults, unmeasured here (debt): 16-pair items every call, the prompt down on at 2,048 pairs and up | `docs/INT4-PORT.md` |

Measured level or negative, deliberately absent with the reason recorded in the file: `CONFIDENCE=-0.20`,
`CHUNK=1536`, `HC_Q12`, `TF_CACHE_EVICT`, `READOUT_FUSE`, `FUSED_SPLIT`, `GREEDY_WIDE=8`, production's six draft
names (no reader here) and `MTP_WEIGHTS=mxfp8` (absent from `dev.env` as unmeasured on r5; the dev launcher sets it
by default, so it is a debt the launcher carries until its own A/B).

## The persistent NVMe KV tier (dev only)

Shape: 8 streams at a 262,144-token window with the page pool (`TF_FLASHNEXT_KV_PAGES=4096`), `--prompt-cache-gib 6`
and the dev launcher's defaults `--prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200
--learn-min-free-gib 20` (`LEARN=0` boots without them). The
plan honours the 6 GiB ask (naming it takes 6.0 GiB out of the pool's pages: 361 pages without it, 278 with), and the
store's budget is the 3,166 MiB `kv_pool.split` hands it - half the ask, the rest set aside for snapshot slots this
family declares no `snap_slots` for. At that budget a 100k state (2.0 GiB) fits and a 261k state (4.7 GiB) does not.
On the shipped r5int4 image, whose engine has no tier patch, the argument check refuses `--learn-conversations`
together with `--prompt-cache-disk`, so a window that needs only the in-RAM cache passes `--prompt-cache-gib 6` alone.

- **Resume.** An appended agent turn resumes instead of re-prefilling: 1.042 and 1.226 s TTFT against 44.206 and
  44.305 s cold, 116.16 and 118.03 MiB a turn. Decode was level in all ten cells (prose and code at 1, 2, 4, 6 and
  8 streams, three timed waves each) under the window's disjoint-range rule; with the control's cold first wave
  excluded, the two arms' warm-wave means agree within 0.4 percent (`docs/receipts/KvTierShip/ev2.tgz`, its
  `tables.md` section 3b), and that rule could not have detected a 2 percent cost
  (`docs/receipts/KvTierShip/RESULT.md` section 2, `docs/receipts/KvTierShip/SHAPES.md`). The replies carry
  identical per-stream sha lists and identical drafted and accepted totals in all 30 wave cells on both arms.
- **Exactness at equal depth** holds at four depths (tails 34, 77, 1,781 and 5,050 tokens at 100k), and five of five
  resume pairs in the dedup lane (`docs/receipts/KvTierW5/RESULT.md`, `docs/receipts/KvTierDedup/RESULT.md`). Two of the four depths also
  have a strict RAM twin (tails 77 and 5,050), which equals the tier cell; the other two (tails 34 and 1,781) are
  ids-equal to their cold twins only, with no RAM twin run. In that table every cell's reply is 320 tokens of the same
  count and shares sha16 `277412fd297b56aa`, including a cold twin whose passage was replaced, so ids-equal shows the
  instruction survived, not that the stored rows are right. A depth difference is the engine's own numerics, not the
  store.
- **Append dedup** (`0022-kv-tier-dedup.patch` of `patches/main-1ece6e6db-r5-kvtier`): 115.1 MiB a turn against 228.1
  for replies under 256 tokens (the mean of turns 6, 8, 9 and 10), so a 60 GiB budget holds 508 such append turns and
  a 100-turn 100k conversation writes 14.1 GiB instead of 25.0. The one shape where the bytes do not halve is a reply
  plus message of 256 tokens or more, where the rewind state is genuinely useful and both arms keep it: turn 7, after
  a 320-token reply, wrote 231.2 MiB on both arms.
- **A rewrite costs a full prefill.** Changing the system message invalidates every state, so that turn pays the cold
  prefill and writes the full row set (`docs/receipts/KvTierW4/RESULT.md`). The tier buys resume time and store bytes, not decode.

- **The page pool's measured value is admission** (`docs/receipts/PagesAudit/RESULT.md`): at 6 and 8 streams the
  unpaged windows are refused by name (31.60 and 42.14 GiB needed against a 22.42 GiB budget) while the paged plan
  admits at 238 pages and 17.14 GiB; where both arms admit, at 4 streams, TTFT and decode are level (-0.5% and
  -0.1% at 32k and 128k, -0.2% prose and -0.4% code, 16 of 16 reply shas identical) and the plan reports 21.47 GiB
  against the unpaged 21.08, so the upstream ~14 GiB saving is not reproducible on this env. On a 129k resume the
  3.1 GiB store keeps one state and the appended turn displaces it, while the unpaged 6.0 GiB cache keeps both;
  the full-ask change is the lever for that.

## The prose gap

Upstream's hard-coded `shared_stop = 0.6` (`zig/src/families/flashnext/cuda_lanes_draft.zig:26`, applied at `:30`) makes
a greedy chain beside another open stream stop on a per-draft threshold whatever `CONFIDENCE` says; it arrived upstream
on 2026-11-10 and the production engine predates it, so production drafted 3.03 tokens a round where ours drafted 1.92
and the difference read as an engine gap. `TF_FLASHNEXT_SHARED_DRAFTS=0` restores the product stop in shared rounds:

| measure (prose, four streams) | baseline | `SHARED_DRAFTS=0` | production |
|---|---|---|---|
| drafted a round | 1.9 | **2.8** | 3.03 |
| acceptance | 0.760 | **0.718** | 0.750 |
| tokens a round | 2.46 | **3.01** | 3.28 |
| ms a round | 46.2 | **51.1** | 51.5 |
| decode, tokens a second | 207.8 | **229.0** | 247.0 |

That is +10.2 percent on prose at four streams and 54 percent of the four-stream prose gap to production, exact
on every arm (drafted equals `"draft": false`, concurrent equals solo, resumed equals fresh) and 7 to 11 percent at
two to eight streams. The residual is drafting volume left in the drafter, not the round: 2.8 drafted a round against
production's 3.03 with acceptance 0.718 against 0.750 (`docs/receipts/ProseDraft/RESULT.md`).

## RigMark + TTFT: `zig/bench/`

AGENTS.md: RigMark is part of every benchmark and client-measured TTFT is a first-class metric. Ported from
glm5.3-flash-dev `scripts/glm53/v110/` (2026-10-10). Box copy `~/work/bench/` (the directory as is, `rigmark/` and
`tests/` included); RigMark itself is spark6 `~/rigmark` at commit `52c29c3fc1d7` (protocol 1.3.0), recorded in spark6
`~/INVENTORY.md`.

- `zab_rm.sh <label> <base arm> <ours arm>` (detached: `setsid nohup bash ~/work/bench/zab_rm.sh L "BASE" "OURS"
  </dev/null >/dev/null 2>&1 &`): an arm is one string of `start.sh` settings (`PREPARE=0
  IMAGE=tensorfold-qwen38:<tag> TF_FLASHNEXT_...`) plus an optional `PATCHES=<the image's OTS patch set>` for the
  metadata; `-` skips an arm. Each arm takes one hold of `~/work/gpu.lock` (~35-55 min) in `ORDER` (default
  `base ours`): boot through `~/work/zarm.sh` with no decode passes, golden against `GOLDEN_REF` (default
  `~/work/zab3/zgold-base-c1.json`, the stock image's replies), the raw SSE of one short reply (SHAPE), `ttft.py`,
  `effort_check.py`, then `rigmark_run.sh` with comparison ID `RIGMARK_ID` (default `zrm-<label>`, one per sweep).
  Log `~/work/bench/zabrm-<label>.log`; summary `python3 ~/work/bench/zab_rm_sum.py <log>`: golden MATCH / DIFF
  per arm, the TTFT and RigMark sections (ours against base), exit 1 on a golden DIFF, a boot, effort, TTFT or
  RigMark error.
- `ttft.py <port>`: TTFT to the first streamed content / reasoning / tool token for cold ~1k / 8k / 32k / 120k
  prompts (a fresh UUID salt each; filler at 21.8 Qwen3.8 tokens a line, measured with the checkpoint's
  tokenizer) with thinking off and on (`chat_template_kwargs.enable_thinking`), and a warm +2k turn on a kept ~100k
  conversation (its first turn re-sent, unmeasured, before each warm sample), each idle and with 3 other streams
  decoding; 3 reps. Per sample the split admit (headers: the Zig server answers after rendering and tokenizing) +
  prefill (the reply's `tensorfold.prefill_seconds`: submit to the first token, so `other` is ~0.01 s at idle) +
  other, beside the server's own `time_to_first_token`; flagged samples (NOTCOLD / NOTWARM / NOLOAD) are printed and
  left out. `ttft.py report <logs>` prints the section. Offline: `tests/test_ttft.py` (a fake server streaming the Zig
  shape) and `tests/mutants_ttft.py` (50 mutants, every flag decision both ways; 50 of 50 killed, 2026-10-10).
- `rigmark_run.sh <label> <comparison-id> <metadata> [extra-body]`: RigMark's standard suite (decode code / prose /
  structured x5 at an 8,192-token cap, cold + immediate-replay prefill 8K / 32K / 64K x3, C1 / C2 / C4 x3) with the
  extra body `{"reasoning_effort": "low"}`, byte-for-byte that of RigMark's published card for this model family
  (`results/reference/qwen38-flash-next-nvidia-nvfp4-tp2-low`: vLLM, two Sparks, NVFP4). The Zig server reads a
  top-level `reasoning_effort` (and `chat_template_kwargs.reasoning_effort`) as the template's effort and turns
  thinking on for any effort but `none`, so every request is thinking on at effort low; `effort_check.py` proves it on
  the live server (`/tokenize` renders the template's low-effort instruction, the reply's `tensorfold` block says
  `enable_thinking` true, `reasoning_effort` low). That card's receipt is protocol 1.1.0 at another RigMark revision
  with a 4,096-token cap, so `rigmark compare` against it needs `--allow-mismatch`; it is a recipe / appliance
  comparison either way. Receipts, cards and filled metadata: `~/work/bench/rigmark/runs/`.
- `rigmark_meta.py`: fills `rigmark/metadata-zig-{stock,ours}.json` (hardware 1x ASUS Ascent GX10) from the serving
  container: engine, image and id, the `tf.patches` label, the OTS patch set (`tf.ots-patches` or the arm's
  `PATCHES=`), model revision, MTP drafter settings, KV dtype, scheduler flags, every `TF_FLASHNEXT_*` /
  `TENSORFOLD_*` setting, the GPU, `/health` (the quiet check). It refuses a template the serve contradicts: the
  engine, model, context, one GB10, the KV dtype / image / env / arguments a template pins, and stock exactly = the
  stock image id + the recipe's `start.sh` env + no OTS patches.
- `rigmark_sum.py`: a receipt's headline line and the RigMark section (per arm the median decode tok/s, last output
  and TTFT per workload, cold / replay prefill, C1-C4 aggregate; errors on a refused run or a mismatched sweep).
- `tests/test_rigmark_dryrun.sh <rigmark clone>`: the whole chain offline against `tests/rigmark_fake_serve.py` (the
  Zig server's routes and stream shape) with stand-in docker / nvidia-smi / zarm.sh / the recipe's start.sh and
  stop.sh / qf_harness.py: RigMark's refusal of a second run on one boot (and a clean run after a restart), the
  metadata refusals, both summaries, `zab_rm.sh` end to end (and no speed probes on a golden DIFF), effort_check.py's
  path. `tests/mutants_rigmark.sh <rigmark clone>`: 31 mutants of those decisions (31 of 31 killed, 2026-10-10), each
  must make the dry run (or test_ttft.py's zab_rm_sum checks) fail. Run both from WSL or a box: `$HOME` scratch, a
  local RigMark clone at the pinned commit.
- `effort_check.py <port> [extra-body]`: the live check that the server honours RigMark's extra body.

Cold prefill and the prompt cache: the Zig server does not read `cache_salt` (unknown request fields are ignored),
and its prompt cache keeps states only at a chat prompt's history (prompts of 4,096+ tokens, in GPU memory).
RigMark's prefill pairs are `/v1/completions` token-id prompts with no history, so they keep nothing: the cold samples
are cold on any run, and RigMark's "immediate replay" is cold too (spark6 2026-10-10: replay cached 0 at every depth,
replay TTFT equal to cold). Our replay column is therefore not comparable with a card whose server caches it (the
vLLM reference: 64K replay 21,923 tok/s); keeping a state for completion prompts would be a server change, not done.

## Build and boot tools

- `zig/target/build_patches.sh TAG REPO BASE PACKAGE` builds one image from a pristine base with a package's patches
  applied in filename order; the TensorFold source is never edited in place.
- `zig/qwen6-start.sh` is the DEV launcher (box copy `~/qwen6-start.sh`); production's launcher is the box's
  `~/qwen6-start-prod.sh`, which is not in this repo and which nothing here edits. The arm's environment is
  `zig/target/env/dev.env`, and `~/work/gpu.lock` serialises every window.

  | launcher | box copy | serve | defaults it states |
  |---|---|---|---|
  | `zig/qwen6-start.sh` | spark6 `~/qwen6-start.sh` | the dev Zig serve (this repo's image + our patches) | `CHECKPOINT=int4`, `VISION=0`, `KV_DTYPE=fp8`, `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`, the KV tier: `--prompt-cache-gib 6 --prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20` (`LEARN=0` off; every value overridable from the environment) |
  | `qwen-start.sh` | spark4, where the retired serve ran (no box copy there today) | the retired Python serve, image `v061-ots` | only `VISION=0` and `KV_DTYPE=int8` (that engine's own default): its recipe `4c0dea8` has no `CHECKPOINT` and its engine TensorFold v0.6.1 has no fp8 KV, no `--learn-*`/`--prompt-cache-disk` and no `TF_FLASHNEXT_MTP_WEIGHTS` reader, so the composition's defaults would be unread or refused there |
  | `~/qwen6-start-prod.sh` | spark6 only (production) | the live serve | production's 54-name environment and its `TF_FLASHNEXT_MTP_FP8` overlay; untouched, and not synced from the repo |

  Which of those defaults already have cells: the tier (`docs/receipts/KvTierShip/RESULT.md`, `docs/receipts/KvTierDedup/RESULT.md`), the INT4 checkpoint with fp8 KV (`docs/receipts/QInt4/RESULT.md`, `docs/receipts/DevVsProd/RESULT.md`), and `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`, which the QInt4 exactness arms ran with (`docs/receipts/QInt4/RESULT.md` env table), so replies are checked with it. It has no own speed A/B on r5, so it is a debt in the register, and `MTP_WEIGHTS=bf16` is its comparison arm. `VISION=0` is the dev serve's shape rather than a measured speed change (`dev.env`; the DevVsProd shape ran vision on and the image's vision helper never came up, so no cell exercised images on either arm).

- **The box copy is the delivery of this launcher.** This file is the record; spark6 runs the copy at `~/qwen6-start.sh`, synced from here (`work/DevEnvComp/READERS.md` records the current pair of shas and the check lines). Re-sync it whenever this file changes and before the next dev boot, never mid-window (this file decides the boot's tier, checkpoint and vision): `scp scripts/qwen38/zig/qwen6-start.sh adam@spark6.ots-int.net:qwen6-start.sh`, then `grep -c TIER_ARGS ~/qwen6-start.sh` reads `3` and `grep -c 'TF_FLASHNEXT_MTP_FP8=' ~/qwen6-start.sh` reads `0`. Never copy this file onto `~/qwen6-start-prod.sh`, which is production's own launcher.

- **The launcher gates.** Two read-only checks, neither boots anything. `python scripts/qwen38/zig/target/env/check-launcher-sync.py --check-local` proves the repo's copies of each launcher are one file (working tree, index and HEAD); `--check-box` reads the box (`--host`, default `adam@spark6.ots-int.net`) and compares the repo copy with `~/qwen6-start.sh`, the box's `~/qwen6-start-prod.sh` with the `production` branch's copy and requires it not to equal the dev launcher, and the recipe launcher's forwarding line with the line recorded at `upstream/recipe-launcher-tf-env/0001-launcher-forward-tf-env.patch` (`--from-file` re-checks a saved probe reply, `--print-remote` prints the probe). `python scripts/qwen38/zig/target/env/check-launcher-contract.py` proves every promoted row of `dev.env` is either stated by the dev launcher at that value, or documented in its own comment as the engine default it is left at (the value and a read site are checked), or carried by the launcher env under a name the recipe launcher's filter forwards; it also proves each switch's `NAME=0` off arm passes that filter, and that the launcher's own gates (`LEARN`, `LOCK_HOLDER`) take a caller's 0. Both exit 0 clean and 1 with one line per finding. The filter is read from the recorded launcher line, never copied into the gate.

- **The tier's spelling in the launchers.** `--prompt-cache-disk DIR` is the engine's own spelling of
  `--learn-conversations --learn-dir DIR` (`zig/src/server/cli.zig:465-469`), and the two spellings are refused
  together (`cli.zig:319-325`, `cli_test.zig:529-556`), so the Zig dev launcher passes the disk form: one flag sets
  `learn_conversations` and the directory, and an engine without the tier patch still takes it (the shipped r5int4
  image refuses the pair by name, `docs/receipts/ProseDraft/RESULT.md`). `--prompt-cache-gib 6` is dev.env's ask (the
  plan grants 3.1 GiB of it).
- The measurement drivers are `zig/target/` (`target_queue.sh`, `zab_rm.sh`'s harnesses, the per-lever arms) and
  `scripts/quality/` (`quality_client.py`, `quality_score.py`, `quality_run_window.sh` for the 1,664-item window).
