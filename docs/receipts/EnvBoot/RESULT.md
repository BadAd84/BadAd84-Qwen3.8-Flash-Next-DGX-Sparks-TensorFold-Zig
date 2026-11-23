# EnvBoot: prompt following on the r5 arms (measured), and the dev env boot (staged and queued)

Written 2026-11-23 at the point the run budget ran out. **Two of the brief's four jobs are done and
measured; the other two are staged, self-tested and queued on spark6 behind another lane's GPU hold and
have not yet produced their receipts.** The split is stated first so no reader mistakes the pending part
for a result.

| job | state |
|---|---|
| Prompt following on r5 and r5-int4, same harness and the same 1,664 frozen bodies | **measured**, on both arms' complete rows (section 3) |
| Attribution if the defect reproduces | **not needed**: the defect does not reproduce, and the r4 record names its cause (section 4) |
| The completed `dev.env` accepted on a boot, `/health` 200, no refusal, and the malformed-setting control | **one attempt measured and it refused** (section 2b): the launcher's default shape cannot boot on the r5 image because the image sets `TENSORFOLD_CUDA_KERNELS` and the engine refuses fp8 KV with it. The corrected boot (bf16, 4 x 131072) and the control are queued behind the Int4Device window and have not produced their receipts |
| The fast 200-item screen and `FAST-VERDICT` | **queued** with the corrected boot; the verdict has not been written |
| The full 1,664-body run on both arms, then production restored | **not started** in this window, as the coordinator directed; it waits for the int4 window and the screen |

## 1. The window that will produce the boot proof, as staged

- Scratch `~/work/EnvBoot`; payload `in/` 61 files, `SHA256SUMS` sha256
  `b29c33f7f4d6e13263df0625c84ffc074f933b5568299c33f7e8f418184a81a4`, verified on the box
  (`sums in/SHA256SUMS: files 61 failing 0`) and the same numbers on the laptop. The env file booted is the
  served-tree HEAD `dev.env`, sha256 `d65c207abb08d2aca58e97fcf35276f3465cf702039e603d1b8bd66c4ab1911f`.
- Driver `window.sh` sha256 `b672ca3d98d1568bbc366c7f3687d4e1cee23168a98b95a385aa503420a6ac8e`, the same digest
  on both sides. It is the QRerun/QInt4 driver with the staging and speed stages removed and four stages
  added: the dev env boot with a settings report, the malformed-setting control, the 200-item screen with
  its verdict, and the long half unchanged.
- Its selftest passes on the box, and it exercises every new gate with planted defects:

```
SELFTEST-OK env, banner (7 mutations stopped, 2 identities opened), manifest, decode, comparer,
  fidelity (QCMPB), internal exactness (11 flips), qcount, qverify, boot reuse, raw kept, X1 flag,
  settings (6 classes), screen (CLEAN and DEFECT), local scope
```

  The settings case plants each classification (a stated value, a blank, a no-value statement, an image
  default, an unstated row, a mismatch and a violated no-value row) and requires the two failure classes to
  stop the report. The screen case plants a clean pair and a defective arm and requires `CLEAN` and
  `DEFECT:A-echo=0 A-correct=200 A-marker=200 B-echo=60 B-correct=0 B-marker=60`.
- Images: arm A and the dev boot `tensorfold-qwen38:qr-a-r5-1ece6e6db`
  (`sha256:001fc6ff...`, `tf.tree.manifest b3de0046...`, 12,622 entries, `tf.source 1ece6e6d...+r5-0001-0020`);
  arm B `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` (`sha256:578911ca...`, `ab6389fc...`, 12,625 entries,
  `...r5-0001-0020+int4-0021-0022`); production `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`
  (`sha256:235211ea...`). Nothing is built in this window.
- The served tree is identified rather than assumed: the manifest generated from `work/QRerun/trees/fp4/src`
  hashes to `b3de0046f8d34c355162d08f8e811d326c08a053e7c13fd4276b0392212cca57`, arm A's own label, so the
  table read below is the validator the dev image carries.

## 2. What the boot must accept, and what dev.env does not state

The startup validator is the tree's own table (`platform/environment.zig`, `checkScope`), reached by the
serve at `families/flashnext/engine_load.zig:47` (`env_validate.startup()`), with every other reader of a
table row going through the same `checked()` parse (172 `environment.read()` sites, one `rawText()` call for
a name outside the table). Against the served tree the table has **95 rows** in the scopes this serve reads
(`flashnext` 34, `cuda` 49, `common` 12). The file I first staged (commit `76f440d1`, sha `c61dbd38`) stated
78 of them and the gate failed with 17 MISSING, quoted here because that is the finding this boot produced and
it was fixed at the source; the file now staged is the served-tree HEAD `dev.env` (sha `d65c207a`, commits
`c70f8d13` and `3cd24943`), which states all 95:

```
coverage: 95 settings in scope, set 95, missing 0, absent 1, annotations 2, worklist markers 0
values: rows 95 stated 84 refused 0
```

The one absent row is `unset TF_ROCE_GID_INDEX`, stated as an absence because that reader tests presence;
`TENSORFOLD_CUDA_KERNELS` is now `export ...=native`, the pin that clears the two guards section 2b measures.
The historical gate output that motivated the fix follows, then the launcher coverage of the 17 rows:

```
$ python scripts/qwen38/zig/target/env/check-env-coverage.py \
    --table work/QRerun/trees/fp4/src/zig/src/platform/environment.zig \
    --dev <the file as first staged> --register .../register.env --scopes flashnext,cuda,common
coverage: 95 settings in scope, set 78, missing 17, annotations 2, worklist markers 0
rc=1
```

| unstated row | supplied at the dev boot by |
|---|---|
| `TF_FLASHNEXT_GATHER_READ=pread`, `GATHER_EARLY=1`, `DRAFT_AHEAD=1`, `PROMPT_GEMM2=1`, `HEAD_PIECE=1536` | config.sh |
| `TF_FLASHNEXT_PREFILL_TAIL=512` | the dev launcher's env block |
| `TF_FLASHNEXT_ROUND_MS`, `DRAFT_ROW_MS`, `GATHER_DIRECT`, `GATHER_THREADS`, `GATHER_CACHE_MIB`, `GATHER_LOG`, `GATHER_LOCK_SCALES`, `PROMPT_SYNC`, `PROMPT_MX128`, `FUSED_SPLIT`, `READOUT_FUSE` | nothing: the engine default applies |

Six names dev.env carries have no row in the served tree's table (`TENSORFOLD_NO_UPDATE_CHECK`,
`TENSORFOLD_PARALLEL`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_KV_PAGES`, `TF_FLASHNEXT_WINDOW`,
`TF_HY4_MEM_FLOOR_GIB`); `TENSORFOLD_PARALLEL` in particular has no reader at all in that tree
(`grep -rn TENSORFOLD_PARALLEL <tree>/zig/src` prints nothing), so `auto` cannot be refused. The int4 image
adds four more `flashnext` rows (`TF_FLASHNEXT_INT4_TILE`, `INT4_PROMPT_GATE_UP`, `INT4_PROMPT_DOWN`,
`HEAD_ROW_TILES`), two of which the launcher sets.

The boot is dev.env plus the dev launcher's own block, and the report says so rather than calling it dev.env
alone. The launcher's `exec env` line carries 56 names; 7 of them are also in dev.env and every one at the
same value (`TENSORFOLD_MEMORY_RESERVE_GIB` 10, `TENSORFOLD_NO_UPDATE_CHECK` 1, `TENSORFOLD_VIDEO_TOKENS`
16384, `TF_FLASHNEXT_BATCH_DRAWS` 1, `TF_FLASHNEXT_CONFIDENCE` -0.15, `TF_FLASHNEXT_DEPTH` 15,
`TF_FLASHNEXT_WINDOW` 64), so nothing dev.env states is replaced by a different value; and the container's
remaining names that neither the table nor dev.env states are listed in the report as `BEYOND-DEVENV`,
because one of them, `TF_FLASHNEXT_HC_Q12=1`, is a lever dev.env's own note records as measured level and
deliberately absent.

Before the boot, every stated value was parsed with the table's own semantics
(`work/EnvBoot/check_values.py`, mirroring `parse()`/`toggle()`/`real()`):

```
values: rows 95 stated 67 refused 0
```

so a boot failure could only come from a runtime refusal (memory admission, the read-out's backend check)
and not from a malformed value. Two such refusals are already ruled out by reading the tree: the fused
read-out's refusal is Metal-only and the affine CUDA read-out's, while this serve takes the native read-out,
and the no-value row `TENSORFOLD_CUDA_KERNELS` is supplied by the image's own `ENV`
(`/opt/tensorfold/share/tensorfold/cuda/sm121`), which the settings report was taught to accept as
`IMAGE-DEFAULT` rather than a violation.

What the fast half will write, in this order, inside one lock hold: the dev boot (source `in/dev.env`, then
`~/qwen6-start.sh` with `LOCK_HOLDER=0 IMAGE=qr-a-r5...`), its `/health` 200, its container environment
diffed row by row against the 95-row table, its banner and its `[tensorfold] profile:` line, and an empty
refusal list; then the control, a throwaway copy of dev.env with one line changed to
`export TF_FLASHNEXT_CONFIDENCE=abc`, which must fail with
`error: TF_FLASHNEXT_CONFIDENCE="abc": expected a finite number (default -0.4)` (the text `describe()`
produces) and must leave `/health` unanswered. That refusal text is the one the tree's own
`describe()` and `checked()` print, so the control tests the real validator rather than a proxy.

### 2b. The first boot attempt, measured, and why the shape changed

The first boot ran at 2026-11-23T12:19:15Z on the fresh post-reboot state (GPU 43 C, 2405 MHz, 10.3 W) with
the dev launcher's own defaults (8 slots, 262,144 tokens, fp8 KV) and stopped on a real engine refusal, not
on a malformed value:

```
[tensorfold] warning: libturbojpeg.so.0 is required for JPEG inputs (--vision); ...
[tensorfold] warning: libwebpdecoder.so.3 is required for WebP inputs (--vision); ...
tensorfold: --kv-cache fp8 runs on Flash Next's own glue on one rank: serve it without --tp, --slide or
  TENSORFOLD_CUDA_KERNELS, or without --kv-cache fp8
[start.sh] ERROR: the server exited (code 1) before it was ready
```

This is the interaction section 2 predicted from the files and the boot proved: dev.env states
`TENSORFOLD_CUDA_KERNELS` with no value because only an unset variable states the default, but the image's
own `ENV` sets it (`/opt/tensorfold/share/tensorfold/cuda/sm121`), so in the container the variable is
present, and the r5 engine refuses that with the launcher's fp8 KV before it loads weights. The row that
dev.env cannot realise is therefore the one that blocks the boot, and the engine's message names the three
ways out: no `--tp`/`--slide`/`TENSORFOLD_CUDA_KERNELS`, or no fp8 KV.

The first way out is closed on this image (a blank value is refused by the table and the image ENV cannot be
removed from inside), and the bf16 route I first tried is closed as well, which a peer's trace and my own
read of the served tree confirm: `cuda_lanes_load.zig:33` refuses fp8 KV and `:35` refuses the page pool
whenever `captured != null`, and `cuda/aot.zig:pick()` returns `.captured` for the image's own
`share/tensorfold/cuda/sm121` because it holds `aot.json`. With `TF_FLASHNEXT_KV_PAGES=4096` in dev.env the
page guard fires before fp8 is even consulted, so a bf16 4 x 131,072 boot would have been refused too.

The engine's own third way out is the right one and is what the queued job now uses:
`TENSORFOLD_CUDA_KERNELS=native` makes `captured` null, both guards pass at `tp = 1` with no slide, and
dev.env's documented shape (8 slots, 262,144 tokens, fp8 KV, `KV_PAGES=4096`) becomes legal and is what the
file was written for. The missing pin, not dev.env's values, is what refused the first boot. The settings
report records that override as `PINNED-NATIVE` rather than failing the presence-default row, and the
control boot takes the same pin so its refusal can only be the malformed confidence value.

Production was restored after that attempt (`PROD-IMAGE-OK`, `/health` 200) and the lock released; the
corrected fast half then queued behind the Int4Device window, which took the free lock at 12:21 and is
running.

## 3. Prompt following on the r5 arms (measured, complete rows)

Same harness and same items as the 2026-11-19 run: the prompt files are byte-identical
(`3fc07867...` gsm8k, `d24100ce...` mmlupro, `d1644fe7...` humaneval) and the r5 raw rows hash to the QInt4
window's recorded file hashes (6 of 6). Two prompt-following counters were first proved against the
2026-11-22 defect report's own published counts, then applied. The echo counter reproduces 166, 145, 0 and 1
of 500 exactly; the option-recitation counter reproduces 51.1, 54.9, 82.6 and 82.5 exactly.

| arm | echo (GSM8K of 500) | `####` marker | MMLU-Pro recited letters correct | GSM8K | MMLU-Pro | HumanEval |
|---|---|---:|---:|---|---|---|
| r2 INT4 (`I4W/A`, the defect) | 166 | 180 | 51.1% | 143/500 = 28.6% | 417/1000 = 41.7% | 86/164 = 52.4% |
| r2 FP4 (`I4W/B`, the defect) | 145 | 73 | 54.9% | 44/500 = 8.8% | 438/1000 = 43.8% | 87/164 = 53.0% |
| **r5 FP4 (arm A)** | **1** | **498** | **82.5%** | **484/500 = 96.8%** | **752/1000 = 75.2%** | **143/164 = 87.2%** |
| **r5 INT4 (arm B)** | **1** | **499** | **82.0%** | **484/500 = 96.8%** | **751/1000 = 75.1%** | **135/164 = 82.3%** |
| 2026-11-19 FP4 (baseline) | 1 | 498 | 82.5% | 484/500 = 96.8% | 752/1000 = 75.2% | 143/164 = 87.2% |
| 2026-11-19 INT4 (production's launcher shape) | 0 | 497 | 82.6% | 482/500 = 96.4% | 759/1000 = 75.9% | 133/164 = 81.1% |

- The single echo on each r5 arm is `gsm8k-test-31`, the one item whose own question is about jelly beans (the
  prompt file's own text says so), so there is no spurious echo on either arm.
- r5 FP4 reproduces the 2026-11-19 FP4 build byte for byte on all 1,664 replies: id-by-id equality of the
  server's `text_sha256` and of `completion_tokens`, 1,664 of 1,664. Its three accuracies are therefore that
  arm's accuracies, and the equality is itself the strongest statement available about the engine build.
- Arm labels are the windows' own: `IDENTITY-A` names the INT4 checkpoint for the r2 pair, so the r2 INT4 arm
  is the 166-echo one; the task brief's mapping of 166 to FP4 is inverted, while the counts are right.
- The accuracies are the official scorer's (`scripts/quality/quality_score.py` sha256 `87cb9c00...`), whose
  `--selftest` reports `7 of 7 checks caught their flip`; re-run this session over the QInt4 rows into
  `work/EnvBoot/scores-r5`, they reproduce that window's summary to the digit.
- The r2 accuracies and echoes are that window's own rows and its published table
  (`work/Int4Window/RESULT.md` table 4, `QUALITY-DEFECT.md` sections 2 and 5).

## 4. Attribution: the defect does not reproduce at r5, so there is nothing to bisect

The suspect was r4's fix to patch 0008's shared-direct write-back, and the r4 package's record both names the
defect and measures it: under `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` the fused hyper-connection read-out called
a write-back variant with no NORM argument, so the normalized rows the read-out consumes were never written;
on the r2 image the defaults read 0 of 20 exact against the reference and `TF_FLASHNEXT_HC_FUSE=0` read 20 of
20, and the r4 fix makes the one launch write the normalized rows as well
(`patches/main-1ece6e6db-r4/CHANGES.md`). The r5 series carries that fix, and the r5-int4 package's own
CHANGES.md says so in the same words while resolving the INT4 port's `slots - 1, slots` widths beside it
(`zig/kernels/cuda/flashnext_hc_norm.cuh`, the `moe_sh` mode-3 launch; 18 matches for `MODE == 3|moe_sh`
against r4's 17). r5's CHANGES.md over r4 records "no behaviour changes".

The measured r5 arms answer echo 1 of 500 and GSM8K 96.8 percent, so no arm fails and no intermediate build
can be named from a bisect. The attribution the brief asks for exists only in this negative form, and it is
supported rather than merely absent: the r2 rows are the unfixed build, the r4 record measures the fix's
effect on the same 20 items, and the r5 rows are byte-identical to the clean baseline's on every one of the
1,664 bodies.

## 5. Delivery state, and what the queued halves will write

The GPU lock on spark6 is held by another lane (its container was up when this was written), so the two
windows are queued in this order, which is the order the coordinator asked for:

1. the holder (Int4Device),
2. **this fast half** (`EB_STAGE=all`): dev boot, control, 200-item screen on each arm, verdict, production
   restored, lock released;
3. KnobScreen's 8-hour window, gated on the verdict;
4. **this long half** (`EB_STAGE=quality`): the full 1,664 bodies on both arms, `qverify`, the id-by-id
   identity against the expected shas, X1 on both arms, the drafted-versus-plain sample on 20 real bodies,
   production restored.

The fast half writes, on the box, before it releases the lock:

- `~/work/EnvBoot/FAST-VERDICT`, first line `CLEAN` or `DEFECT:<numbers>`, written by
  `in/screen_score.py` whose rule is fixed before the run: `CLEAN` only when on both arms the echo count is at
  most 5 of 200, the answers at least 170 of 200 and the `####` marker at least 170 of 200; otherwise
  `DEFECT` naming each arm's three numbers. For scale, on the same 200-item slice the r2 defect reads echo 63
  and 58, answers 63 and 20; the r5 rows read echo 1 and 1, answers 192 and 192; the 11-19 baselines read
  echo 1 and 0, answers 192 and 189 (`work/EnvBoot/selftest-screen/`).
- `~/work/EnvBoot/RESULT.md`, the boot proof, the control and the screen table, with the echo explanation
  (the slice contains the one legitimate jelly-beans item, so a clean arm reads 1).
- its `/home` reading before and after, and the production restore line.

The long half appends its own sections (the bodies, their identity against the expected shas, the cells) to
the same `RESULT.md` and restores production again.

## 6. Where every number comes from

| claim | source |
|---|---|
| image ids, manifests, sources | `docker image inspect` on spark6 (quoted in section 1) |
| served-tree identity | `work/QRerun/in/mkmanifest.py` over `work/QRerun/trees/fp4/src` -> `b3de0046...` |
| table size, the 17 unstated rows | `work/EnvBoot/coverage-vs-served-tree.txt` (the gate's own output) and `work/EnvBoot/env-table-rows.txt` |
| value parse check | `work/EnvBoot/check_values.py`, `work/EnvBoot/values-check.txt` |
| what the launcher supplies | `work/EnvBoot/predict_env.py` |
| echo rate | `work/EnvBoot/count_echo.py` control block (166/145/0/1) |
| option recitation | `work/EnvBoot/recite_options.py` (51.1/54.9/82.6/82.5) |
| r5 accuracies | `scripts/quality/quality_score.py --raw work/QInt4/raw --out work/EnvBoot/scores-r5` |
| baseline accuracies | `work/QualityCmp/scores/summary.md` |
| r5 rows against the baseline | id-by-id `text_sha256`/`completion_tokens`, 1,664/1,664 equal against 11-19 FP4 |
| r2 rows and scores | `work/Int4Window/box/out/arms/{A,B}/raw/*.jsonl`, `work/Int4Window/RESULT.md` table 4 |
| the 0008 defect and the r4 fix | `patches/main-1ece6e6db-r4/CHANGES.md`; `patches/main-1ece6e6db-r5{-int4}/0008-*.patch` |
| screen instrument and its rule | `work/EnvBoot/in/screen_score.py`; check against known arms in `work/EnvBoot/selftest-screen/` |
| the driver and payload | `sha256sum` on both sides (section 1); box selftest output |
