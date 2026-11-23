# DevEnvBoot: the env of record booted as written, its container env proved, one cell set measured (review F1)

Status: **one measured boot**, 2026-11-23 18:50:49 to 19:00:21 UTC on spark6, one hold of `~/work/gpu.lock` (18:50:49
to 19:00:21), production restored from the driver's EXIT trap and pinned (`PROD-IMAGE-OK`, `/health` 200, image
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea...`). The image booted is
`tensorfold-qwen38:qr-a-r5-1ece6e6db` (`sha256:001fc6ff...`, the served r5 tree), the file is
`scripts/qwen38/zig/target/env/dev.env` at HEAD `77401164` (`sha256:e464f1d6...`), and the environment the container
carried matches the file at every name the launcher can carry. **This is a first boot, not a verdict**: one boot, one
shape, no arm, and the only same-harness baselines are on the INT4 checkpoint while this boot serves the FP4 one. The
cells below are therefore a first reading, and section 5 says exactly what they may and may not be used for.

## 1. The boot, as the launcher takes the file

The file is sourced the way the window has always sourced it, then the dev launcher runs with its hold off:

    ( set -a; . in/dev.env; set +a; cd "$HOME"
      timeout 2400 env LOCK_HOLDER=0 IMAGE=tensorfold-qwen38:qr-a-r5-1ece6e6db \
        PARALLEL=8 CONTEXT=262144 WARM_TURNS=0 "$HOME/qwen6-start.sh" </dev/null )

- **Shape**: 8 slots, 262,144-token window, fp8 KV, vision on, drafts MTP, port 8888. The container's own
  `.Config.Cmd` reads `--context 262144 --parallel 8 --max-tokens 32768 --kv-cache fp8 --vision ...`, the FP4
  checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local @ b9ce18a6`.
- **Wall**: 52 s from launcher start to `/health` 200 (`out/DEVENV/boot_time-8-262144.txt`).
- **Boot line**: `nvidia/Qwen3.8-Flash-Next-FP4-Local · 8 at once · 262144-token window · fp8 KV · vision on ·
  drafts MTP · port 8888`.
- **Plan**: `model 83.00 GiB; 8 streams at once, the engine's own at a 262144-token window (5.35 GiB, in the
  model's), 7 more taking 190 pages of 4096 rows (13.68 GiB) as they need them, 84 MiB fixed each, of 19.7 GiB left
  after a 10.0 GiB reserve; prompts in passes of up to 16384 rows, no prompt cache; own glue kernels`.
- **Pages**: one page 73.75 MiB, 4096 rows; 18.44 KiB a token; the state run 673.39 MiB on 10 pages (8.7 percent
  padding); the snapshot 110.29 MiB on 2 pages.
- **Profile**: `stable; registered overrides: TF_FLASHNEXT_KV_PAGES=4096 (experimental, env)`, so the only
  experimental override the engine registered is the page pool, as the file intends.
- **Copy window**: `info: flashnext: window self-check: 1176 of 1176 rows byte-equal to their one-token steps
  (widths 1-48)` and `serving 48-row copy windows after the self-check`. `TF_FLASHNEXT_WINDOW_CHECK=1` therefore did
  run on this image and proved the 48-row window; the fail-closed 32-row path was not taken.
- **`/health`**: `{"status": "ok", "model": "Qwen3.8-Flash-Next", "max_batch_size": 8, "backend": "cuda",
  "device": "NVIDIA GB10", "version": "1.3.0"}`.
- The warnings on the boot are `start.sh`'s memory note (8 full windows are ~40 GiB of fp8 cache beside ~81 GiB of
  weights, so a request that would not fit is refused), the two vision library warnings (`libturbojpeg.so.0`,
  `libwebpdecoder.so.3`), the non-loopback no-API-key note, and the missing `libtfgrammar.so` (structured output and
  tool calls only). There was no refusal and no error line.

Why the earlier attempt at 13:49 refused, recorded because it changes the reading of that receipt: the file staged
then was NOT HEAD. It still carried `export TF_FLASHNEXT_KV_PAGE_TEST=0` (line 233), and the engine refuses the text
`0` by name (`cuda_pages.zig:69-71`, absence is the only off). HEAD carries `unset TF_FLASHNEXT_KV_PAGE_TEST`
(line 241) and the same image boots on the same shape. The 13:49 refusal was the stale file's line, not the kernel
pin, not `KV_PAGES`, and not the shape.

## 2. The container env against the file: PROOF OK

`docker inspect`'s `.Config.Env`, filtered to its 122 names matching `TENSORFOLD_|TF_`, was diffed name by name
against the file's 100 exports and 2 unsets, and against the served tree's 95-row validator table
(`out/DEVENV/envdiff.txt`, produced by `in/envdiff.py`).

    SUMMARY carried 74 equal, 0 differ, 0 absent-in-namespace; unset 2 ok, 0 violated; inert 26 not forwardable;
    table 95: match 64, mismatch 0, blank kept 4 filled 0, absent-default 2, image-default 0, violated 0,
    not-carried 25, unstated 0; beyond-dev-env 48; levers 8/8 ok
    ENV-PROOF OK

- **Every name the launcher can carry reads the file's value.** 74 dev names are in the launcher's forward
  namespace, all 74 present and equal; 0 differ, 0 absent. The two `unset` lines are absent from the container as
  intended (`TF_ROCE_GID_INDEX`, `TF_FLASHNEXT_KV_PAGE_TEST`).
- **The eight recipe levers read their served values**: `DRAFT_AHEAD=1`, `GATHER_EARLY=1`, `GATHER_READ=pread`,
  `HEAD_PIECE=1536`, `KEEP_LATE=1`, `PREFILL_TAIL=512`, `PROMPT_GEMM2=1`, `WARM_AHEAD=1`. None read an engine
  fallback.
- **The 95-row table**: 64 match, 0 mismatch, 4 blank rows kept blank (`TENSORFOLD_TOOL_ID_KEY_FILE`,
  `TF_FLASHNEXT_ROUND_MS`, `TENSORFOLD_HIP_MEMORY_LIMIT_GB`, `TF_FLASHNEXT_PROMPT`), 2 absent-default rows absent
  as stated, 0 violations, 0 unstated. `TF_FLASHNEXT_KV_PAGES` is not a table row, so its proof is the direct diff
  and the profile line above.
- **26 dev names cannot reach the container at all**, because the served recipe's `start.sh` forwards only names
  matching `^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+$`:
  `TF_CACHE_EVICT, TF_STARTUP_RECEIPT, TF_SHARED_PRICE_LOG, TF_NCCL_LIB, TF_CUDA_DEVICE, TF_CUDA_SEGMENTS,
  TF_CUDA_CARVEOUT, TF_CUDA_CARVEOUT_MIB, TF_MTP_DRAFTS, TF_DSPINE_WINDOW, TF_DRAFT_NODES, TF_QMMF_HALF_BELOW,
  TF_HY4_MEM_FLOOR_GIB, TF_QWEN_KEEP_LATE, TF_QWEN_KV_PAGE_TEST, TF_COST_KEY_TRACE, TF_TIMING, TF_NO_TREES,
  TF_MTP_TREES, TF_MTP_BATCH, TF_QWEN_POOL_LOG, TF_Q27_POCKET_OFF, TF_Q27_TAIL, TF_Q27_GEMM,
  TF_PROMPT_INTERMEDIATE, TF_QWEN35_CHUNK_SOLO`. Every one of them states the engine's own default value, so the boot
  behaves exactly as if the line were absent, which is what the file's explicit-defaults section wants. But the
  "no setting may be unset" rule is met on paper only for those 26: the launcher would have to forward them (a
  `start.sh` filter change) before their absence could ever be noticed. 25 of the 26 are validator rows, which is why
  the table reads 25 not-carried.
- **48 names the boot carries that neither the file nor the table states**: the launcher's own block, including
  `TF_FLASHNEXT_HC_Q12=1` (a lever the file records as deliberately absent and does not set), `COPY_*`, `MULTI_*`,
  `NGRAM_*`, `FP8_FUSED_SPLIT=4`, `QSA_*`, `SEQ_POOL=8`, `PREFILL_ROWS=4096`, `SOLO_MAX=1024`,
  `TENSORFOLD_PROMPT_CACHE_WHOLE=1` and `TENSORFOLD_WARM_TURNS=0`. The full list is `out/DEVENV/envdiff.txt`'s
  `BEYOND-DEVENV` rows. They are the launcher's, not the file's, and the review's F1 correctly said the file cannot
  control them.

## 3. The cells on that boot

All cells ran against the same boot, in the order decode, cold TTFT, exactness, fixed-prompt replay. Every decode
cell has `failed 0` and `unmeasured 0`. The baselines are ProseDraft's S0 arm, taken on
`tensorfold-qwen38:qr-b-r5int4-1ece6e6d` (the INT4 checkpoint) with the tree's default chunk of 3,072 rows
(`work/ProseDraft/out.fetched/out/B0a/plan.txt`, `work/ProseDraft/RESULT.md` section 3).

| kind | streams | this boot, tok/s | S0 (INT4, gate off), tok/s | ratio | B0 (INT4, gate on), tok/s | ratio |
|---|---:|---:|---:|---:|---:|---:|
| prose (chat) | 1 | 55.1 | 70.3 | 0.784 | 69.9 | 0.788 |
| prose (chat) | 4 | 176.7 | 229.0 | 0.772 | 207.8 | 0.850 |
| code | 1 | 84.1 | 97.0 | 0.867 | 97.2 | 0.865 |
| code | 4 | 266.0 | 300.1 | 0.886 | 276.8 | 0.961 |

The rate is a product of tokens a round and milliseconds a round, and this boot's own `done` lines say why it is
lower (means over the 256-token requests of each cell):

| cell | drafted a round | acceptance | tokens a round | ms a round | S0: drafted / acc / tokens / ms |
|---|---:|---:|---:|---:|---|
| prose 1 | 6.14 | 0.424 | 3.61 | 67.0 | 3.1 / 0.655 / 3.0 / 42.7 |
| prose 4 | 5.60 | 0.457 | 3.56 | 81.6 | 2.8 / 0.718 / 3.0 / 51.1 |
| code 1 | 7.49 | 0.658 | 5.93 | 72.8 | 4.8 / 0.776 / 4.7 / 48.7 |
| code 4 | 7.26 | 0.679 | 5.93 | 90.8 | 4.2 / 0.804 / 4.4 / 57.2 |

The stop settings are identical on both sides: `CONFIDENCE=-0.15` and `DRAFTS=6` are stated in S0's own container
environment (`work/ProseDraft/out.fetched/out/S0a/env.txt`), `SHARED_DRAFTS=0` is S0's arm, and `DRAFTS_GREEDY=8`,
`GREEDY_WIDE=4` and `WINDOW_ROWS=64` are S0's engine defaults which this container carries explicitly at those
values. So the deeper chain is not a different stop threshold.

The chains are drafting over different text. On the chat prompt, all four of the S0 and B0 boots (S0a, S0b, B0a,
B0b) return the same reply, `sha=e4cb0b3b74d7`, and their one-stream counters agree (`rounds=85 accepted=171/261`);
their four-stream requests return the same reply again. This boot returns `sha=b6849d9aee81` on the same prompt at both one and
four streams, so the model is writing different prose before any counter is compared, and the draft acceptance
follows the text. The difference appears with the checkpoint (the two INT4 boots agree with each other and the FP4
boot does not), and a near tie moved by the four prefill-side levers cannot be excluded; either way the counter table
above is context, not a comparison.

**Cold TTFT** (`in/ttft.py`, the GapArms instrument, thinking off, idle, 3 reps):

| cell | this boot | baseline | ratio | baseline source |
|---|---:|---:|---:|---|
| cold 2k | 0.945 s (prefill 0.884) | none | - | no receipt measures a 2k cold cell |
| cold 32k | 13.034 s (prefill 13.012) | 12.593 s | 1.035 | GapArms C4a, chunk 4096, same INT4 image (`work/GapArms/RESULT.md`) |
| cold 32k | 13.034 s | 12.916 s | 1.009 | GapArms C3a, chunk 3072, same INT4 image |

The 2k samples were 0.953, 0.945, 0.885 s; the 32k samples 13.013, 13.034, 13.098 s, `cached 0`, none excluded.

The probe's warm case also ran because I did not pass `--warm-add 0`. Its three samples are all `NOTWARM` and
excluded from the medians, and they are a usable side reading: a 102k prompt cold-prefilled in 43.754, 43.925 and
43.920 s (`prompt 102119, 102155, 102102`, `cached 0`), against the tier window's recorded no-tier cold twins of
44.206 and 44.305 s (`work/KvTierDedup/RESULT.md`) and GapArms' 43.934 to 44.087 s. On this image a 100k cold
prefill sits at or slightly under those records.

**Exactness on the boot itself** (`--alone --serial`, 64 greedy tokens): every concurrent reply's token hash equals
its solo run (1 of 1 at one stream, 4 of 4 at four streams, both prompts), and every solo reply equals its
`"draft": false` twin (1 of 1 each, with 51 and 49 drafts accepted and 0 tokens drafted on the plain side, so the
check is not vacuous). Drafted equals plain and concurrent equals solo on this boot.

**Fixed-prompt replay** against the r5 FP4 record (`in/hashcheck.py` over `in/expected-text-shas.tsv`, arm R5A):
2 of 3 frozen GSM8K items match the record's `text_sha256` and completion tokens exactly.

    HASH-MATCH     gsm8k-test-0  sha16=6317d4155d51eab6  tokens=62
    HASH-MATCH     gsm8k-test-1  sha16=cdb107390d9dd5cd  tokens=68
    HASH-MISMATCH  gsm8k-test-5  want=970afa1fdbc6d8f9 138 tok  got=2712e985bd0d533a 144 tok

`gsm8k-test-5` is the one item whose record already disagrees with itself across the four recorded arms: R5A (FP4)
138 tokens and Q19B (FP4) 138, R5B (INT4) 140, Q19A (INT4) 142, with four different shas. It is build-sensitive, so
it is a weak oracle for an environment change either way. The two matching items are FP4-only values (the INT4 arms
read 76 and 49 tokens on them), so the corrected environment reproduces the FP4 record where the record is stable.
This is three items, not the 1,664-body identity run; that run was not part of this window.

## 4. The pool grant, and the tier flags this boot did not pass

- `TF_FLASHNEXT_KV_PAGES=4096` (positions a page) was accepted; the plan granted **190 pages** of 4096 rows, 13.68
  GiB, beside the first stream's own 5.35 GiB window. A full 262,144-token window on a paged lane takes
  `mostPages` = 65 pages, so the pool holds 2.9 paged windows: the eight slots are admitted, but they cannot each be
  given a 262,144-token window, and start.sh's warning says a request that would not fit is refused. On the INT4
  image, ProseDraft's B0a boot of the same recipe at the same 8 x 262,144 shape took 327 pages
  (`work/ProseDraft/out.fetched/out/B0a/plan.txt`), so the grant is image-dependent: 83.00 GiB of FP4 weights leave 19.7 GiB after the 10 GiB reserve.
- The tier flags are not passed by this boot: no `--prompt-cache-gib`, no `--prompt-cache-disk`, no `--learn-*`, so
  the plan reads `no prompt cache` and the tier is not exercised. The file's `KV_PAGES` comment describes a launcher
  that carries those flags; this launcher does not, and the comment's cache numbers (3.1 GiB granted of 6 asked) are
  from the INT4 shape, so this boot neither confirms nor refutes them. The review's F2 keeps that point.

## 5. What this boot proves, and what it does not

Proves: the file as written boots the r5 FP4 image at its documented shape with no refusal; every name the launcher
can carry arrives with the file's value; the eight levers arrive at their served values; the window self-check runs
and proves 48-row copy windows (1176 of 1176 rows); the drafter is exact against solo and against `"draft": false`;
production was restored and pinned.

Does not prove, and must not be quoted as:

- **Speed parity with the receipts.** Every baseline this window compares against was measured on the INT4
  checkpoint (ProseDraft's dev image `qr-b-r5int4`, GapArms' C3/C4 arms of the same image, and even ProseDraft's
  "production" anchor P1, whose banner in that window reads the INT4 checkpoint). No decode cell on the FP4
  checkpoint exists in this work tree's receipts. The deltas above are therefore a first reading of the FP4 image, not a measurement of the four levers or
  of the file. The baselines return one reply on the chat prompt and this boot returns another (section 3), so the
  texts being timed differ before any knob is considered; this window cannot separate checkpoint from environment,
  and a like-for-like arm (the INT4 image booted with this file) was not run.
- **A verdict on the eight levers.** Each was measured on the INT4 image in its own window; this boot confirms they
  arrive and that the boot runs, not that their gains add up.
- **The prose 4-stream figure as the env's speed.** 176.7 against S0's 229.0 is a 22.8 percent gap and 55.1 against
  70.3 a 21.6 percent gap at one stream, with code at 13 and 11 percent. For scale, the recipe's own r5 FP4 image
  has never had a decode cell, and the numbers this window compared against are the INT4 arm's. **If the file is to
  be promoted for both images, its measured block needs a per-image arm, or its header must say the numbers are the
  INT4 checkpoint's.** That is a finding for the review, not an edit made here.
- **The tier, the identity of 1,664 bodies, or the prompt cache.** Not exercised (section 4), and the hash cell is
  three items.
- **Noise discipline.** One boot, three reps a cell, no repeat boot and no disjoint-range rule; the receipt rule
  wants two boots an arm before a cell is called separated, so nothing here is called faster or slower than a
  receipt.

## 6. State left behind

- Production restored at 19:00:21 UTC: `prod /health 200 (start rc 0) image
  tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`,
  `MARK PROD-IMAGE-OK`, and the lock was released. The next holder (TierFollowup's window) took the lock and stopped
  production for its own boot minutes later, which is the protocol, not a failed restore.
- `/home` before: 982,819,848,192 B total, 798,376,726,528 used, 134,443,085,824 available (86 percent), with
  `/home/adam` at 328,766,836 KiB. After: 798,377,840,640 used, 134,441,971,712 available, `/home/adam` at
  328,768,136 KiB, i.e. 1.3 MB more, which was the window's own receipts; those were fetched and the lane directory
  removed, so the net after cleanup is nil.
- Nothing installed on the box; the lane directory `~/work/DevEnvBoot` and its tarball were removed after the
  receipts were fetched. The GPU lock is free of this window.
- No host gate ran: this lane changed no code and needed no build. The executable evidence is the boot's own
  environment validator, the window self-check, the exactness cells and the env diff.

## 7. Where every number comes from

The paths below are the box's `~/work/DevEnvBoot/out/...`; the fetched copy in this repo is
`work/DevEnvBoot/out-fetched/out/...`.

| claim | source |
|---|---|
| boot, shape, wall, `/health`, image id | `out/DEVENV/{boot_time-8-262144.txt,health.json,container-image.txt,cmd.txt}`, `out/run.log` |
| boot lines (banner, plan, pages, profile, self-check, copy window) | `out/DEVENV/{banner-line,plan-line,pages-line,profile-line,selfcheck-final,copy-line}.txt` |
| env proof, levers, inert names, beyond list | `out/DEVENV/envdiff.txt` (tool `in/envdiff.py`), table `in/env-table-rows.txt` regenerated from the served tree and HEAD's file |
| decode cells | `out/CELLS/conc_L{1,4}.json` (`bench_concurrent.py`, sha256 `269fc2eb...`, the same file both baselines used) |
| round counters | `out/CELLS/rounds{1,4}.log`, the server's own `done ... rounds= accepted=/drafted=` lines |
| cold TTFT | `out/CELLS/ttft_cold.out` (`ttft.py`, sha256 `7fd729ad...`) |
| exactness | `out/CELLS/exact_L14.json` |
| fixed-prompt replay | `out/CELLS/hash/gsm8k.jsonl`, `out/CELLS/hashcheck.txt` |
| restore and home | `out/RESTORED`, `out/run.log`, `out/home-{before,after}.txt` |
| driver and payload | `out/run.log` `SCRIPT window.sh sha256 c5cc5924...`, `out/preflight-sums.txt` (16 files verified) |
| baselines | `work/ProseDraft/RESULT.md` section 3 and `work/ProseDraft/out.fetched/out/S0a/`, `work/GapArms/RESULT.md` prefill section and `out.fetched/out/C4a/ttft_cold.out`, `work/KvTierDedup/RESULT.md` |
