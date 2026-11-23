# scripts/qwen38 - the Qwen3.8 Flash Next serve

**Live: the Zig serve on spark6 `:8888`.** Production is started by the box's `~/qwen6-start-prod.sh`; the repo's
launcher is `zig/qwen6-start.sh` (box copy `~/qwen6-start.sh`), the same image and the same serve:
image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, INT4-AutoRound, fp8 KV, 8 streams at
a 262,144-token window, thinking on by default (`chat_template_kwargs.enable_thinking=false` turns it off). Boot 83 to
90 s at one to eight streams (`docs/SPEED-TARGET-1.2.6.md`); golden 6/6 identical to stock on the first boot. It holds
the box's GPU lock while it runs, and spark6 has no passwordless sudo, so arms bind to 127.0.0.1 and production is
restored from its own launcher.

## Our arm (`main`)

- **Series.** `patches/main-1ece6e6db-r5` (0001 to 0020) on upstream main `1ece6e6db`, with
  `patches/main-1ece6e6db-r5-int4` (0021, 0022) for production's INT4-AutoRound checkpoint and
  `patches/main-1ece6e6db-r5-kvtier` (the NVMe KV tier) on top. Build:
  `zig/target/build_patches.sh TAG git://192.168.99.16/up-pr/tf 1ece6e6db <package>`. Stock for a series A/B is
  upstream main at the base built with no patches; the last full A/B of the series is
  `patches/main-964174ea05/README.md`.
- **At production's shape** (8 x 262,144, fp8 KV, production's 54 names plus the page pool) the INT4 arm reads 0.79 of
  production on prose and 0.95 on code at eight streams, level on code at one, two and four; cold prefill is level at 1k
  and 19 to 22 percent behind at 8k and 32k (`work/DevVsProd/RESULT.md`).
- **Quality: an open defect.** The 2026-11-22 window on the r2 tree scored GSM8K at 8.8 percent (FP4) and 28.6 percent
  (INT4) against 96.8 and 96.4 on 2026-11-19, because the build answered a few-shot example instead of the question (166
  of 500 GSM8K replies on FP4 and 145 of 500 on INT4 name the jelly-beans example, against 0 and 1). The 0008
  shared-direct write-back is the prime suspect and its r4 fix is in the series, but no r5 or r5-int4 prompt-following
  run exists yet and the re-run is queued: internal exactness is no evidence here (`work/Int4Window/QUALITY-DEFECT.md`,
  and `docs/INT4-PORT.md` has the full reading).

## The environment

`zig/target/env/dev.env` is the arm's environment of record and `prod.env` is the live launcher's copy: the 54
settings read from the running container on 2026-11-23. The rule (`docs/ENV-REGISTER.md`): **every setting the served
tree reads is SET in `dev.env`**, because presence is what an upstream rebase silently inherits and a value in the
engine's source is invisible to a name-level sweep. The file writes the measured settings below with the record that
proved each one, then every remaining setting the served tree reads at its own read site's default with that read
site quoted; a value that is not the engine default belongs in the measured list with its cells.
The setting-by-setting verdicts and the ranked worklist are in `docs/KNOB-COVERAGE.md`.
`zig/target/env/check-dev-env.py` fails on a missing setting, on a value carried only by a note in `register.env`, and
on a worklist line; `update-env-register.py --defaults-from-tree` builds the worklist.

| setting | value | measured or carried | record |
|---|---|---|---|
| `TF_FLASHNEXT_PROMPT_SHARED_DIRECT` | `1` | +1.2 percent at 8k and +1.0 at 32k cold prefill, decode level | `work/SDFix/RESULT.md`, `work/PatchBisect/RESULT.md` |
| `TF_FLASHNEXT_READOUT_FUSED` | `1` | +3.19 to +6.47 percent cold TTFT, decode level, tokens equal | `work/KnobTest/receipt/w1`, `work/RoGpu/receipt/cold.md` |
| `TF_FLASHNEXT_CHUNK_SOLO` | `16384` | +1.12 to +1.39 percent at 32k and 64k, 2k and 8k level | `work/KnobTest/VERDICTS.md` |
| `TF_FLASHNEXT_CHUNK` | `4096` | +3.6 to +4.1 percent cold TTFT at 1k, 8k and 32k | `work/GapArms/RESULT.md` |
| `TF_FLASHNEXT_WINDOW_CHECK` | `1` | +26 and +12 percent on verbatim and one-word copy turns, fail-closed at 32 rows | `work/upsubmit/PrCopyWindow/pr-body-g.md` |
| `TF_FLASHNEXT_KV_PAGES` | `4096` | the shape needs it (39.90 GiB against 31.00 without it) and it is the tier's page pool | `work/KvTierShip/RESULT.md` |
| `TF_FLASHNEXT_SHARED_DRAFTS` | `0` | +7 to +11 percent at 2 to 8 streams; prose 229.0 against 207.8 tokens a second at four | `work/ProseDraft/RESULT.md` |
| `TF_FLASHNEXT_CONFIDENCE` | `-0.15` | production's launcher value, not a measured lever on this tree (-0.20 is level on prose); the FP4 1.2.7 stack's own optimum was -0.4 (`patches/1.2.7/README.md`), so the value is checkpoint-specific | `work/ProseDraft/RESULT.md`, `work/ProseDraft/POLICY.md` |
| `TF_FLASHNEXT_BATCH_DRAWS`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_WINDOW`, `TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_NO_UPDATE_CHECK`, `TENSORFOLD_VIDEO_TOKENS` | `1`, `15`, `64`, `10`, `1`, `16384` | production's launcher values carried unchanged; `DEPTH` and `WINDOW` have no reader in this tree | `work/ProseDraft/POLICY.md` |

Measured level or negative, deliberately absent with the reason recorded in the file: `CONFIDENCE=-0.20`,
`CHUNK=1536`, `HC_Q12`, `TF_CACHE_EVICT`, `READOUT_FUSE`, `FUSED_SPLIT`, `GREEDY_WIDE=8`, production's six draft
names (no reader here) and `MTP_WEIGHTS=mxfp8` (not re-measured on r5).

## The persistent NVMe KV tier (dev only)

Shape: 8 streams at a 262,144-token window with the page pool (`TF_FLASHNEXT_KV_PAGES=4096`), `--prompt-cache-gib 6`
and the launcher's `--prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20`. The
planner grants 3,166 MiB of the 6 GiB asked, so a 100k state (2.0 GiB) fits and a 261k state (4.7 GiB) does not. On the
shipped r5int4 image, whose engine has no tier patch, the argument check refuses `--learn-conversations` together with
`--prompt-cache-disk`, so a window that needs only the in-RAM cache passes `--prompt-cache-gib 6` alone.

- **Resume.** An appended agent turn resumes instead of re-prefilling: 1.042 and 1.226 s TTFT against 44.206 and
  44.305 s cold, 116.16 and 118.03 MiB a turn, every reply byte-equal to its no-tier twin, decode level in all 30 cells
  at 1, 2, 4, 6 and 8 streams (`work/KvTierShip/RESULT.md`, `work/KvTierShip/SHAPES.md`).
- **Exactness at equal depth** holds at four depths (tails 34, 77, 1,781 and 5,050 tokens at 100k), and five of five
  resume pairs in the dedup lane (`work/KvTierW5/RESULT.md`, `work/KvTierDedup/RESULT.md`). A depth difference is the
  engine's own numerics, not the store: the RAM twin at the same depth equals the tier cell.
- **Append dedup** (`0022-kv-tier-dedup.patch` of `patches/main-1ece6e6db-r5-kvtier`): 115.1 MiB a turn against 228.1
  before it, so a 60 GiB budget holds 508 append turns and a 100-turn 100k conversation writes 14.1 GiB instead of
  25.0. The one shape where the bytes do not halve is a reply plus message of 256 tokens or more, where the rewind state
  is genuinely useful and both arms keep it (231.2 MiB on both).
- **A rewrite costs a full prefill.** Changing the system message invalidates every state, so that turn pays the cold
  prefill and writes the full row set (`work/KvTierW4/RESULT.md`). The tier buys resume time and store bytes, not decode.

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

That is +10.2 percent on prose at four streams and 54 percent of the gap to production, exact on every arm (drafted
equals `"draft": false`, concurrent equals solo, resumed equals fresh) and 7 to 11 percent at two to eight streams. The
residual is drafting volume left in the drafter, not the round: 2.8 drafted a round against production's 3.03 with
acceptance 0.718 against 0.750 (`work/ProseDraft/RESULT.md`).

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
- `zig/qwen6-start.sh` is production's launcher (the box runs it as `~/qwen6-start-prod.sh`); the arm's launcher is
  `zig/target/` with `env/dev.env`, and `~/work/gpu.lock` serialises every window.
- The measurement drivers are `zig/target/` (`target_queue.sh`, `zab_rm.sh`'s harnesses, the per-lever arms) and
  `scripts/quality/` (`quality_client.py`, `quality_score.py`, `quality_run_window.sh` for the 1,664-item window).
