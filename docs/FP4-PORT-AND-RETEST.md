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

- SUPERSEDED by section 6: the stall was the pre-custody upload path (file-backed mmap sources), fixed upstream on
  2026-10-18 and by 0050 on our tree; stock v1.1.4 and v1.2.4 boot kindling (131 s and 35 s). The DGX OS fallback
  below is no longer needed for upstream artifacts:
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

## 6. 2026-11-07: the hang solved, the series retired upstream, the parity measurement

Current state. Section 4's "stock main does not boot on kindling" and section 5's open-PR list are superseded here.

- **The 64 KiB-page boot hang: cause and fix.** A pageable host-to-device copy whose source is the file-backed safetensors
  mmap hangs in the driver on kindling once the process holds device memory (the class of GLM's `ots0073` and the
  ai-engine kindling patch `0002-native-upload-mmap-stage`). The CUDA 13.3 compat lib is NOT the cause: `zmerge8-kfix`,
  `zig-db28187` and `fp4port` all carry the same `libcuda.so.610.43.02`, and `zmerge8-kfix` boots kindling in forward-compat
  mode with it. Fix 0050 (`7163805` on `fp4port`): `zig/src/cuda/memory.zig DeviceBuffer.upload`, the single chokepoint of
  all 69 `.upload(` callers, stages every blocking upload through a 1 MiB anonymous stack block; 0049 (weights path only)
  reverted. With it the main-based image loads in 48.4 s on kindling, golden 6/6 identical to stock, `exact.py` PASS.
- **Three port defects the host suite could not see**, all in files it never compiles: 0043 had dropped all 28 `TF_QMMF(`
  and 14 `TF_QMMF_LD(` instantiations (restored `9c13e75`); 0048 left two orphaned macro continuations in the `.cu`
  (`5aef693`) and built the fused LD kernel name with the fn_qmmf tail and looked it up in the fn_qmmf module
  (`2662507`, `cf5807d`, now pinned by a test). The lane's `test.sh` gained a `.cu` gate (no instantiation line vanishes
  since the recipe tip; every changed `.cu` compiles under the base image's nvcc) and an `ld_` module-handle grep.
- **Upstream had already fixed the hang**: TensorFold copy custody (`096200f02`, 2026-10-18; `copy_source.zig`
  `syncChunk` stages every synchronous upload through an anonymous 64 MiB chunk) is in v1.1.4 and later. The recipe's
  2026-10-30 rewrite re-pinned to **v1.1.4** (`eab8582`) with 17 new patches and retired the whole `db281878` series our
  port targets; our PRs #34-#63 are closed (only #53's fill fix survives, as his 0021). 0050 is therefore
  `db281878`-only; no upstream submission. The `fp4port` branch is backed up at `ots/tensorfold-fp4port` on Gitea.
- **v1.1.4 facts measured on spark6**: the published image (`tensorfold-qwen38:v1.1.4-eab8582`, digest in the recipe's
  `config.sh`) boots kindling in 131 s with no hang. `CHECKPOINT=int4` is refused by its engine (`UnsupportedCheckpoint`:
  the AutoRound layout); it serves NVIDIA FP4 only, and 6 or 8 streams do not fit at 262,144 tokens (the recipe's own
  note). Golden against the 1.0.0 INT4 reference: 4/6; the two differences are wording changes from the quant
  ("Return" vs "Returns the n-th Fibonacci number", "examine the integers" vs "examine each integer"), not truncation.
- **Upstream TensorFold is v1.2.4** (`267c5af6`, 2026-11-07): 2,610 commits past the pin, 332 files in the Flash Next
  family / lanes core / CUDA runtime. It carries equivalents of three of the recipe's 17 (lane-batched DeltaNet, `KEEP_LATE`,
  the running-product stop rule), paged KV (`TF_FLASHNEXT_KV_PAGES`) and a 19%-sooner first token for short prompts; it
  still lacks our 12-bit hc read-out, copy re-sync / shared ramp, warm turns for Flash Next and the sequence pool of
  kept graphs. 15 of the recipe's 17 patches fail `git apply --check` on 1.2.4: a recipe bump is a rebase of the
  maintainer's own series. Our levers therefore target TensorFold main, not the recipe.
- **The serve**: `scripts/qwen38/zig/qwen6-start.sh` (zmerge8-kfix, INT4, 8 streams, warm turns off); the parity
  drivers are `scripts/qwen38/zig/par114/` (stock v1.1.4 on NVFP4 vs ours on INT4, cross-quant by necessity, plus a
  stock upstream 1.2.4 arm).

### 6.1 Parity matrix, 2026-11-07 (spark6, kindling, fresh boot per cell, ABBA order, sparkDash stopped)

Decode = aggregate tok/s, median of 3 passes of 512-token greedy replies with every slot busy (`tfm_decode.py`);
TTFT = client-measured cold prompts, thinking off, with C-1 other streams decoding (`ttft.py`). Both arms golden-clean
on their own terms (ours 6/6 identical to the 1.0.0 INT4 reference; stock 4/6, the two being quant wording changes).
Boot: ours 86-93 s, stock 131-142 s. Raw cells: spark6 `~/work/lanes/par114/runs/`, summariser `par114/sum.py`.
TTFT columns are the C-1 load level (C-1 other streams decoding). Ours ran 8-13 C hotter at decode (the ABBA order
put it second in three of five pairs), which understates ours by about 1-2% on the thermal doc's envelope.

| streams | prose stock / ours | code stock / ours | TTFT 1k stock / ours | TTFT 8k | TTFT 32k | TTFT 120k |
|---|---|---|---|---|---|---|
| 1 | 57.2 / 69.4 (+21%) | 77.5 / 112.3 (+45%) | 0.57 / 0.41 | 3.26 / 2.62 | 12.9 / 10.6 | 52.0 / 42.4 |
| 2 | 67.0 / 101.1 (+51%) | 112.9 / 173.4 (+54%) | 0.65 / 0.45 | 3.51 / 2.66 | 13.7 / 10.7 | 54.9 / 42.6 |
| 4 | 97.9 / 152.1 (+55%) | 145.5 / 226.5 (+56%) | 0.71 / 0.50 | 3.68 / 2.70 | 14.3 / 10.7 | 56.6 / 43.5 |
| 6 | 118.6 / 187.3 (+58%) | 166.5 / 281.8 (+69%) | 0.77 / 0.48 | 3.73 / 2.70 | 14.5 / 10.8 | 57.4 / 43.1 |
| 8 | 133.5 / 210.9 (+58%) | 196.4 / 328.6 (+67%) | 0.77 / 0.49 | 3.77 / 2.72 | 15.0 / 10.7 | 58.5 / 43.0 |

Ours is ahead at every level on every metric (no regression anywhere, so serving it is not a trade); the gap is the
levers of section 6's table plus whatever the INT4 versus NVFP4 kernel paths contribute (the maintainer's own ledger
puts his INT4-era build 7% above his v1.1.4 build on code at 5 streams). Stock's TTFT grows with load (1k 0.60 idle
to 0.77 at 8 streams); ours stays flat (0.45 to 0.49).

**Stock upstream TensorFold v1.2.4** (`tensorfold-qwen38:up124`: `267c5af6` built without any recipe patch, NVFP4,
vision off, bf16 KV because its Flash Next family refuses `--kv-cache fp8`, 131,072-token windows; 8 streams do not
fit: 32.9 GiB of bf16 cache against 31.4 free) is the slowest of the three on decode and TTFT and the fastest to boot
(35 s): prose / code aggregate 50.0 / 70.5 (1 stream), 68.7 / 103.9 (2), 94.7 / 129.2 (4), 115.5 / 166.3 (6); cold
TTFT 8k / 120k with 3 other streams 4.69 / 75.5 s. Against it the recipe's own patches measure 0 to +14% on decode
(largest at 1 stream, nil at 6) and ours a further ~50%: bringing 1.2.4 into the recipe as it is would give both up.

### 6.2 Lever 1 on TensorFold 1.2.4: copy re-sync and the shared-round copy ramp (2026-11-07)

Branch `port-copy-windows` (`f738706e0` on `267c5af6a`, 8 files +308/-20; backup Gitea `ots/tensorfold-levers124`),
lane report `agent://CopyWindows124` of this session, driver `scripts/qwen38/zig/par114/abq.sh`, cells spark6
`~/work/lanes/par114/runs2/`. Our 0104's window step is already upstream (`5bb64597d`: copy windows to 32 rows, a lone
stream ramps 15 to 31); the port adds what upstream lacks: a copy that misses mid-edit keeps its source and resumes
(`TENSORFOLD_COPY_RESYNC`, `_PROMPT_ONLY`), the ramp policy (`TENSORFOLD_COPY_MISS` first|keep, `TENSORFOLD_COPY_RAMP`
double|jump) and shared rounds taking the lone ramp when the last copy came from the prompt (`TENSORFOLD_COPY_SHARED`).
All off by default, strict values. The 64-row window is NOT ported: upstream's `exact_width` is 32 and raising it is a
kernel row-invariance claim with its own receipt.

Gates: `zig fmt` clean; lean_check 116 / 116 problems (0 new, each tree its own copy); host suite 7701/7768 vs
7697/7764 (+4 tests added, the same 3 pre-existing environment failures); 2 mutants killed (the prompt-only gate, the
miss arming). Exactness: golden 6/6 identical to stock up124's own replies on every cell, `exact.py` PASS on both arms
with the same six shas and 555 accepted drafts, every copy/rewrite/edit reply sha equal between arms.

Measured (NVFP4, bf16 KV, 131k windows, fresh boot per cell, ABBA, medians of 3; stock up124 / cw124 tok/s):

| streams | one-word rewrite | two concurrent edits (1st / 2nd) | edit beside prose (edit / prose) | verbatim copy |
|---|---|---|---|---|
| 1 | 231.0 / 300.9 (+30%) | | | 375.8 / 375.8 |
| 2 | 228-231 / 298-300 (+30%) | 140 / 199-201 (+42-45%), 140 / 210-213 (+49-52%) | 147-150 / 233-234 (+57%), 47-48 / 50 (+4-6%) | 374-377 / 374-376 |
| 4 | 227.9 / 295.8 (+30%) | 137 / 198 (+44%), 138 / 210 (+52%) | 147 / 232 (+58%), 47 / 50 (+5%) | 372 / 371 |
| 6 | 230 / 296-300 (+29%) | 138-143 / 199-203 (+42-44%), 139-143 / 210-213 (+49-51%) | 148-149 / 231-233 (+56%), 48 / 49-50 (+4-5%) | 376 / 372-376 |

Plain decode and TTFT: two boots a cell at 2 and 6 streams gave opposite signs (pass 1 cw124 -4.3% prose at 2 and
-4.0% at 6; pass 2 +3.9% and +3.7%), means within 1%; 1 stream +4.4% prose / +0.8% code, 4 streams +0.1% / 0.0%. TTFT
equal within 1-2%, cw124 marginally higher in 7 of 8 loaded cells inside that spread. So plain decode is bounded at
about +-2% (two boots, opposite signs, means within 1%): not shown to regress, and not claimed as no-regression either.
8 streams is not measurable on either arm here: stock 1.2.4 refuses 8 at bf16 KV (needs 32.86 GiB, the budget leaves
31.41 at 131,072 tokens), so the levels are 1/2/4/6. Peak GPU 77 C (copy probe), boots 34-36 s. sparkDash was
restarted mid-pass by a safety timer; every cell's SOURCES line shows 127.0.0.1 only, request counts equal between arms.

The same lever against the other families: GLM 5.3 PRODUCTION is the Python engine (tf-v110 on spark1-3, not the Zig
build), which has its own copy-proposal machinery and already widens its windows through the recipe's `COPY_MAX` (up
to 63, `recipe-copy-windows.patch`, the F72 file-copy-and-rename decode in glm5.3-flash-dev's production doc); the
resync, ramp and shared-round rules are NOT in it (no such knobs in the production doc), so they are candidate work
measured on the production serve. The Zig `glm` family is a separate artifact (32-row windows, no resync knobs
either). DeepSeek V4.1 keeps its own suffix-lookup drafting (families/deepseek_v41/draft/lookup.zig) and the lane
core is shared; the wiring is per family and unmeasured.

### 6.3 Lever 2 on TensorFold 1.2.4: the 12-bit hc read-out - measured negative (2026-11-07)

Branch `port-hc-q12` (`24f70f52b` on `267c5af6a`, 10 files +559/-8, the read-outs as a sixth qmmf mode, exact by
construction; image `tensorfold-qwen38:hq124`; backup Gitea `ots/tensorfold-levers124` branch `port-hc-q12`).
Gates: `zig fmt` clean; lean_check 116 / 116 problems, 0 new; host suite 7701/7768 vs 7697/7764 with the identical
3 pre-existing environment failures.

Measured (both arms on `267c5af6`, NVFP4, bf16 KV, 131,072-token windows, two boots at 1 and 2 streams, one at 4 and
6, fresh boot per cell, ABBA, spark6 `~/work/lanes/par114/runsHQ/`): **no measurable change at any level.** Per-stream
medians (stock / port, tok/s): 1 stream prose 52.3 / 52.7, code 73.6 / 73.6; 2 streams prose 39.1 / 39.2, code 53.4 /
53.5; 4 streams prose 26.6 / 26.5, code 39.4 / 39.3; 6 streams prose 22.6 / 22.2, code 33.2 / 32.7. The copy, rewrite
and edit probes are equally flat (rewrite 226-230 on both arms at every level; edits 136-140 vs 139-140 at 6 streams).
Every cell byte-identical: golden 6/6 against stock's own replies at all four levels, all SOURCES 127.0.0.1.

Verdict: the +2.6-3.7% the 12-bit read-out measured on the 1.0.0 engine does not reproduce on 1.2.4 - that engine's
hc read-out kernels no longer leave the cost the old patch removed. No PR. The negative is recorded so the lever is
not retried; the branch and image stay for reference.

### 6.6 Warm turns on 1.2.4: the family never declared them - ported, measured, keep (2026-11-08)

Branch `port-warm-turns` (`ed50016cdf` on `267c5af6a`, image `tensorfold-qwen38:wt124`; backup Gitea
`ots/tensorfold-levers124` branch `port-warm-turns`). The v1.2.4 lane core runs warm turns end to end
(`lane_host_warm.zig`, pre-emption at any chunk, the `quiet()` window, `server/warm.zig` prefilling the next turn)
for any family declaring `warm_quiet`; only `nemotron` did, and the core hard-coded Nemotron's quiet constant. The
port adds the two Flash Next declarations (`warm_quiet = 150 ms`, `warm_opt_in = true`), moves the quiet through
`api.Info.warm_quiet_ns`, and reads `TENSORFOLD_WARM_TURNS` strictly (exactly "1"/"0"/unset/empty; anything else
refuses the start). Gates: fmt clean; lean 116 / 116, 0 new; host suite 582/585 with the failing-test list
identical to pristine base (the 3 pre-existing environment tests).

Measured (6 cells, one fresh boot per cell, `~/work/lanes/par114/runsWT/` via `arm_wt.sh`, `wtsum.py`; 24/24 boots
golden 6/6, workload shas one distinct per (streams, kind)): **next-turn warm TTFT -38 to -45%** (up124 / wtoff /
wton, median of 2: 8k 0.694 / 0.690 / 0.405, 32k 0.787 / 0.834 / 0.482, 100k 1.225 / 1.136 / 0.671 at 1 stream;
the same shape at 2 streams), with the second turn's prompt fully cached (100,782 / 100,802 rows). **The trade is
real but only in the sub-second-after-reply window**: a fresh 8k prompt sent 0.2 s after a reply costs +8.6% (c1)
/ +6.3% (c2); at 1.0 s and 3.0 s pauses it is within noise (+0.3 to -0.6%). Decode, TTFT idle/loaded and the
copy/rewrite/edit workloads are equal on all arms. Boot +0-4 s; the `nvidia-smi` memory query is N/A on GB10, so
the memory delta is the boot log's sequence-memory line (unchanged).

Verdict: **keep, behind `TENSORFOLD_WARM_TURNS`** - off by default (the trade is the owner's to accept per the
fleet rule), and worth it for any agent workload whose turns are >1 s apart, which is all of ours in practice.

**Gates re-run on the final head `7bf66d350` (2026-11-08 08:2x GMT, `~/work/lanes/port124c/results-gates124.log`):**
lean 130 / 130 problems, 0 new (the port's two multi-line comments fixed in `7bf66d350`); `zig fmt --check` clean;
the host suite builds 581/585 steps on base and head with the identical failing-test lists - the three pre-existing
environment tests (one listener test needing a network, two `drama_voice_tool` cleanup tests expecting
`error.AccessDenied` as root) plus two steps that fail in both trees; per-test pass counts equal (7695/7764 both).
The PR's tests line is now filled and no re-run is owed.

**Rows64on124's final report (2026-11-08) sharpens 6.5 in three ways, all verified on the box:**
- The 49-row boundary has a NAMED mechanism: the pending-row log capacity (`batch.late_rows = 48`) - the fused GDN
  kernel writes no log, so a verify window past 48 rows takes the row-by-row GDN path and errors `UnexpectedTensor`
  (its own commit `6cc40677d` proves the failure mode). Reaching a true 64 rows needs the late-log path row-exact
  past 48, which is upstream work.
- The PR head is `7bf66d350` on Gitea branch `port-64rows-v2` (the two comment-checker fixes; `port-64rows` keeps
  the pre-fix line). The receipt's boot lines are from `8a83b6352`; `7bf66d350` is comment-only on top.
- One measurement negative, stated: at 6 streams (single boots) w64 read -2.3% code / -4.5% prose aggregate. The
  decode path is identical between arms (shared rounds never use copy windows), so it is recorded as unexplained
  single-boot variance, not a mechanism - a re-run belongs in the next window that touches this engine.

**Box state after the 64-row window (2026-11-08 08:1x GMT):** the production serve back up through
`~/qwen6-start.sh` (zmerge8-kfix, /health ok, its lock holder re-armed) and sparkDash active - restored by hand
after the window's trap left the serve down (its restore guard saw the lock free but skipped the start; the guard
script's log has no entry, so the box sat dark ~35 min until the manual restore). The restore guard needs the same
conditional-start the driver trap has; noted for the next lane brief.

### 6.5 The 64-row copy window on 1.2.4: the invariance boundary is 48 rows (2026-11-08)

Branch `port-64rows` (`427063f62` on `267c5af6a`, 5 files +113/-9: `max_rows` 32 -> 64, the boot-time self-check
(`probeServed`) with automatic 32-row fallback per load, `TF_FLASHNEXT_WINDOW_CHECK=0` as the skip; image
`tensorfold-qwen38:w64` = `ee54ffa645f3` no-cache from the branch; backup Gitea `ots/tensorfold-levers124` branch
`port-64rows`). The self-check on the real weights measured the row-invariance boundary directly: **widths 1-48 are
byte-equal to their one-token steps at every row; width 49 is the first that differs** (1,176 of 2,080 rows equal
across widths 1-64). The engine served 48-row windows and logged the fallback - the designed worst case is exactly
stock behaviour. First smoke run aborted correctly on the missing `tf.kernels=embedded` label (the boot never
happened; label added, re-run).

Measured (both arms on `267c5af6`, NVFP4, bf16 KV, 131,072-token windows, boot-split medians, ABBA; spark6
`~/work/lanes/par114/runs64/`): **the 48-row windows are worth it, and the boundary is the receipt.** Verbatim copy
**374.3 -> 473.7 tok/s (+26.6%)**, one-word rewrite **228.8 -> 256.7 (+12.2%)**; two concurrent edits and
edit-beside-prose flat within the boot spread (edits 141.1/141.3 vs 137.7/138.6, editprose 147.7/47.4 vs
147.8/47.4). Plain decode flat at every level (prose 51.9 vs 51.9, code 72.8 vs 72.3 at 1 stream; all six-boot
medians within 1.5%). Memory: +0.05 GiB a stream (4.11 -> 4.16 GiB at 2-6 streams), zero pool-reservation delta,
no level refused. Golden 6/6 vs `zgold-up124.json` on all 24 boots; sparkDash incidents: one mid-pass restart by a
safety timer, every SOURCES 127.0.0.1.

**Default-on: yes at 48 rows, on this checkpoint.** The self-check makes it safe by construction (any failing shape
serves upstream's 32-row windows, worst case = stock), the memory cost is ~50 MiB a drafting stream, and the win is
+26.6% on the workload that dominates agent file edits. The 49+ row regime needs its own invariance work and is not
claimed. PR text: fill `upstream/tensorfold-pr-copy-resync/PR_64row.md` from this section.

### 6.4 Settings retune on 1.2.4: keep both defaults (2026-11-08)

Sweep (`~/work/lanes/par114/runsTUNE/`, per-boot dirs with `SUMMARY.md`, 20 valid boots, ABBA, two boots a cell at
1 and 2 streams; driver `tune_sweep.sh`, summariser `tsum.py`, the `tune*` case in `arm.sh`): **keep
`TF_FLASHNEXT_CONFIDENCE=-0.4` and `TF_FLASHNEXT_PRODUCT_STREAMS=5`.** `CONFIDENCE=-0.15` costs 9.0% prose and 4.3%
code at 1 stream (its one positive, +3.6% prose at 2, is paired with editprose -3.2% and appears nowhere else);
-0.3 is the same shape smaller; `PRODUCT_STREAMS=6` loses 4.3% prose / 2.2% code at 6 streams where the cap binds
(byte-identical in construction at 4 and below, +0.4/+0.3% measured, noise). TTFT flat everywhere; 66-76 C; 20/20
boots golden 6/6 vs `zgold-up124.json`. The old stack's -0.15/-0.3 preference does not transfer to 1.2.4 on FP4.

Negatives stated: base C=2 has one boot (its twin died to a sibling's mid-window `arm.sh` write; the top-up
deadlocked against the restored serve's holder and the lock passed to the 64-row lane), and the corrupted
`tune-base-c1-b6` boot is excluded with its clean `b21-r1` re-run standing. C=4/6 are single-boot cells, bounded by
the ~+-1% C=1/2 spread. No PR, no commits on spark6; the box restored (serve /health ok, sparkDash active).
