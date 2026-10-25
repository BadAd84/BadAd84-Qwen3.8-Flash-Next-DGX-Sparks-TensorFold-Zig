# FP4 port and re-test (started 2026-10-25)

Everything needed to continue the upstream work after the 2026-10-25 PR 34 re-test: what is known,
which of our patches are at risk on the FP4 default, and the working measurement procedure.

## 1. What happened upstream (2026-10-25)

- @plotarmordev re-tested #34 (`TF_FLASHNEXT_CONFIDENCE=-0.15`) on current main `656879fd75` with the
  NVFP4 checkpoint: no gain at 1 client, 1-3% slower at 2/4. #57 (`PREFILL_ROWS=4096`) partially
  reproduced (+3.8-4.5% at 32k).
- We re-ran their exact protocol as a 2x2 (checkpoint x setting), spark6, stock main, DGX OS 4K
  fallback, `VISION=0`, fresh boots in ABBA order, GPU temp sampled per window, `bench_streams.py
  --decode-only --streams 1,2,4 --tokens 512 --reps 3`. Per-stream tok/s, both boots of each arm:

  | checkpoint | cell | default (`-0.4`) | `-0.15` | change |
  | --- | --- | ---: | ---: | ---: |
  | NVFP4 (main default) | prose 1c | 53.4 / 52.6 | 52.6 / 51.7 | -1 to -2% |
  | NVFP4 | code 1c | 53.8 / 53.1 | 51.9 / 51.6 | -3% |
  | NVFP4 | code 2c | 48.1 / 48.7 | 40.3 / 41.3 | **-15 to -16%** |
  | NVFP4 | prose 4c | 44.2 / 43.6 | 42.5 / 41.9 | -4% |
  | INT4-AutoRound | prose 1c | 63.2 / 62.3 | 63.9 / 63.6 | +1 to +2% |
  | INT4 | code 1c | 68.8 / 67.6 | 73.8 / 73.4 | **+8 to +9%** |
  | INT4 | code 2c | 62.7 / 62.9 | 68.3 / 67.3 | **+8%** |
  | INT4 | code 4c | 56.0 / 55.5 | 60.4 / 59.9 | **+8%** |

  Raw log: spark6 `~/work/pr34_arms.log` (arms 1-4 NVFP4, 5-8 INT4; order D,C,C,D per checkpoint).
- Conclusion: on FP4 we AGREE with upstream (neutral at 1c, clear regressions behind it); on INT4 the
  setting is a code win (+8% at every width, every -0.15 boot above every default boot). The original
  +10.1% prose figure does not survive main's config either (it was measured under the INT4-era
  defaults: `PRODUCT_STREAMS` 2, no `DEPTH` cap, `PARALLEL` 8, plus our patch stack). The knob's
  optimum is jointly checkpoint- and config-dependent.
- Our reply is posted (PR #34, comment 6396852666): proposes closing #34 or scoping the export to
  `CHECKPOINT=int4`; also flagged their bench anomalies (2-stream per-stream beating 1-stream; prose
  1-stream replies truncating at 252/512 tokens), the thermal-methodology point, and the cold-cache
  VisionTimeout boot loop.
- All campaign measurements (the +8-13% stack gains and every PR number) were taken 2026-10-08..11 on
  stock DGX OS (4K), on INT4, BEFORE spark6 moved to kindling (2026-10-12) and BEFORE main gained the
  NVFP4 default. OS is not a confound between our claims and their re-tests; checkpoint and config are.

## 2. Open risk: none of our engine patches have been measured on FP4

Upstream will re-test each patch ("ported in order once the exactness runs pass"). Nobody knows which
of our wins survive on the NVFP4 checkpoint. Coupling score = lines mentioning int4/gptq/nvfp4/modelopt/mxfp8:

| risk | PR / patch | coupling | note |
| --- | --- | --- | --- |
| high | #56 / 0024 prompt-tiles | 80/818 | half of it is the int4 prompt kernel for the experts' gate/up: inapplicable to NVFP4 experts; the block-FP8 tile half unproven there |
| high | #50 / 0020 draft-stop-lines | 41/443 | includes the int4 lm_head as draft head |
| medium | #36 / 0011+MTP_FP8, #47 / 0017 | 35/730, 10/668 | MTP draft on block FP8; FP4's MTP experts are already MXFP8, so the premise may be moot or different |
| low | #54 12-bit read-outs, #55 indexer, #63 shared-expert, #42 n-gram host, #43-#45 copy windows, #62 whole-prompt states, #46 seq-pool | 0-11 | generic mechanisms; should carry |
| known | #34 confidence | - | proven to flip on FP4 (section 1) |

Structural blocker: main's NVFP4 support (its patches 0011/0012 `*-nvidia-fp4`) postdates our batch.
Our series was written against a tree with no FP4 load path and main renumbered its patch set
(0001-0015), so OUR patches must be ported onto main's current series before any FP4 measurement.

## 3. Plan (continue from here)

1. Port the risky three first (#56 prompt-tiles, #50 draft-stop-lines, #36 mtp-fp8) onto main
   `656879f`'s patch series; then the rest as one stack (our campaign order: 0010-0024 equivalents).
2. Exactness first on FP4: golden 6/6, `tools/exact.py` + `--pad 3k`, `tools/needle.py`
   (`bench_draft`/`exact_prefill` named in their triage do not exist; our stand-ins are in the
   PR-34 batch note).
3. Speed: stack-vs-stock, fresh boots interleaved, decode at 1/2/4 streams for triage (full
   qualification stays 1/2/4/6/8 per the fleet rule), TTFT first-class, RigMark for published
   numbers. Record GPU temp at each timed window (`docs/GB10-THERMAL-BENCHMARK-METHODOLOGY.md`).
4. Reframe or withdraw what does not survive BEFORE their re-tests land; update PR texts with the
   FP4 numbers the same way #34 was answered.

## 4. Measurement environment that works (spark6 procedure)

- **Stock main does NOT boot on kindling (64K pages)**: the engine stalls at ~2.8 GiB during load
  (single core spinning; our OTS 64K loader fix is what our own images carry). Test upstream
  artifacts on the DGX OS 4K GRUB fallback:
  - to DGX OS: `ssh -A adam@192.168.99.16 'sudo sparkos-rollback'`
  - back to kindling: `ssh -A adam@192.168.99.16 'sudo sparkos-rollback 0.9.5-1019-64k'` (promoted,
    TRIAL=0, becomes the default again). ~90-150 s per reboot; /home and /var/lib/docker persist.
- **`VISION=0` unless vision is under test**: on a cold kernel cache the vision helper's first-boot
  work outlasts the engine's VisionTimeout (`tensorfold: --vision: the helper stopped before it was
  ready (VisionTimeout)`) and boots loop forever; the helper's build does not persist in the cache.
  With VISION=0, main boots and serves in ~4 min per arm on either checkpoint.
- start.sh `WAIT_TIMEOUT` defaults to 1800; per-arm scripts used 600. Env passthrough: every
  `TF_FLASHNEXT_*` in the launching shell reaches the container (start.sh ENV_ARGS loop).
- Bench harness (theirs, stdlib-only, run on-box): `python3 tools/bench_streams.py
  http://localhost:8888 --decode-only --streams 1,2,4 --tokens 512 --reps 3`.
- Worktree: `git -C ~/qwen-zig worktree add ~/qwen-stock 656879f` (removed after the re-test;
  recreate the same way). Both checkpoints are already staged in spark6's HF cache: nvidia FP4-Local
  @ `b9ce18a6` (96G) and azampatti INT4 @ `14642741` (122G), both at main's pinned revisions.

## 5. State left behind (2026-10-25)

- spark6 back on kindling, INVENTORY updated. `tensorfold-qwen38:zig-db28187` on spark6 is now the
  LOCAL build of main 656879f (patches `c0a2df4c680d`); the campaign's stock 1.0.0 image is still
  recoverable: `docker tag ghcr.io/miaai-lab/qwen3.8-flash-next-single-dgx-spark-tensorfold:zig-db28187-4144696f21e3 tensorfold-qwen38:zig-db28187`.
- Evidence logs on spark6: `~/work/pr34_arms.log` (the 2x2), `pr34_prepare.log`, `pr34_int4boot.log`,
  `pr34_dbgboot.log`; arm driver script `~/work/pr34_arms.sh`.
- Our open PRs upstream: #34-#36, #42-#50, #53-#63 (all open, none merged; maintainer triage
  2026-10-11 deferred GPU exactness). Watch for more plotarmordev re-tests.
