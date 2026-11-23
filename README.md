# qwen3.8-flash-next-dev

Development of OTS's Qwen3.8 Flash Next serve on spark6 (`:8888`, one Spark): the MiaAI-Lab recipe, our levers as
patches on upstream TensorFold main, their tests and benchmarks, and the upstream PRs. Split out of ots-infra on
2026-10-08 (the history up to the split stays there: ots-infra `git log -- scripts/qwen38 upstream/qwen-pr-*`).

The hardware - the Sparks, provisioning, what runs where - is ots-infra's (`ots-infra/docs/INFRA-LAYOUT.md`,
`ots-infra/docs/NEW-SPARK-SETUP.md`). The GLM-5.3-Flash serve on spark1-3 is glm5.3-flash-dev.

## Now (2026-11-23)
- **Production (spark6 :8888):** image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, INT4-AutoRound, fp8 KV,
  8 streams at 262,144, its own launcher `~/qwen6-start-prod.sh`; the measured target is the `production` branch's
  `production/SPEED-TARGET.md`.
- **Our arm (`main`):** `patches/main-1ece6e6db-r5` (+ `-r5-int4`, + `-r5-kvtier`) on upstream main `1ece6e6db`, env
  in `scripts/qwen38/zig/target/env/dev.env`; at production's shape it reads 0.79 prose / 0.95 code of production at 8
  streams (`work/DevVsProd/RESULT.md`), and `TF_FLASHNEXT_SHARED_DRAFTS=0` is promoted (7 to 11 percent at 2 to 8
  streams).
- **Quality, open:** the r2 build answered a few-shot example instead of the question (GSM8K 8.8 percent on FP4 and
  28.6 on INT4, against 96.8 and 96.4 on 2026-11-19); the 0008 shared-direct write-back is the prime suspect and its r4
  fix is in, but no r5 or r5-int4 prompt-following run exists yet (`work/Int4Window/QUALITY-DEFECT.md`).

## docs/
- **`ENV-REGISTER.md`** - the setting rule and its gate: every setting the served tree reads is set in `dev.env`.
- **`OPEN-PR-COVERAGE.md`** - our pull requests, merged and open, the part fix, and each one's state.
- **`INT4-PORT.md`** - serving production's INT4-AutoRound checkpoint on our engine: the port, its speed cells, PR
  #4183's state and the open quality defect.
- **`SPEED-TARGET-1.2.6.md`** - the target: the `production` branch's own `SPEED-TARGET.md`, reproduced.
- **`RECIPE-PATCHES-VS-UPSTREAM.md`** - whether upstream covers the recipe's 17 patches (checked against 1.2.4).
- **`UPSTREAM-WATCHLIST.md`** - the upstream recipe and engine, sectioned by date.
- **`GB10-THERMAL-BENCHMARK-METHODOLOGY.md`** - the GB10 sustained clock/power/thermal envelope: clocks sag ~4% in
  50 s and settle ~2170-2200 MHz at 80-83 C with no throttle bits, so benchmarks interleave arms, record start temps
  and never compare differently-hot boxes; also why `nvidia-smi -lgc` is not a speed lever.
- **`AFFINE3-TILE-MISPICK-2026-11-06.md`** - the affine-3 routed expert kernel's decode-tile mis-pick at 4 rows.

## scripts/qwen38/
The serve: the MiaAI-Lab recipe on spark6, our levers as numbered patches (`patches/main-1ece6e6db-r5*`), the
environment (`scripts/qwen38/zig/target/env/`), the build and boot tools (`scripts/qwen38/zig/target/build_patches.sh`,
`scripts/qwen38/zig/qwen6-start.sh`), the benchmarks (`scripts/qwen38/zig/bench/`), and the quality harness
(`scripts/quality/`). `scripts/qwen38/README.md` is the SSOT: the env, the series and each lever's measurements.

## patches/
`patches/main-1ece6e6db-r5/` is every change we own on upstream main `1ece6e6db`, one lever a patch, with
`main-1ece6e6db-r5-int4/` and `main-1ece6e6db-r5-kvtier/` on top; `patches/1.2.6/` and `patches/1.2.7/` carry the same
levers cut against v1.2.6 (`6e9af9302`) and v1.2.7 (`93a2e93ec`). Each package has `RECORD.md`, `SHA256SUMS` and
`apply.sh`.

## upstream/
The parked recipe PR packages (`qwen-pr-*`) and the Zig and TensorFold packages (`zig-pr-*`, `tensorfold-pr-*`), each
with its `RECORD.md` and `SHA256SUMS`; `BATCH-2026-10.md` and `compile_batch.py` write the batch texts.
