# ProdEnvAudit: the production engine's complete env record

Written 2026-11-24. Every figure below is a line a command printed in this session; the command is named
beside it. Nothing was built, no GPU was taken, no container was started or stopped, and production was
read only through its build source and the parity window's phase-0 capture.

## 1. The production engine, and the table it does not have

The production engine is the tree the served image was built from, not the dev composition:

| reading | value | command |
|---|---|---|
| image | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` | `docker image inspect` on spark6 |
| image id | `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f` | same |
| source label | `ai-engine.src-sha256 = e5139fcd8c6101c7` | same |
| source tar | spark6 `~/work/ots201/build/src.tar`, sha256 `e5139fcd8c6101c776d9c600021228d389e648f58a398842498d95c3ebcccecc`, 29,962,240 bytes; kept at `work/ProdEnvAudit/src.tar` (gitignored), with every cited file copied into `src/` | `sha256sum`, `stat -c %s`, `tar -tf` |
| entries | 1743, of which 1640 regular files | `tar -tf ... \| wc -l`, `tar -tvf ... \| grep -c '^-'` |
| tree match | the production branch tree at `5c3e3e29` (`work/prod`): **1640 files, 1640 common, 0 only, 0 differing** | `python work/ProdEnvAudit/cmp_tree.py work/ProdEnvAudit/src work/prod` (`tree-compare.txt`) |

**The engine has no settings table.** The dev tree carries `zig/src/platform/environment.zig`; the
production tree does not:

```
$ tar -tf work/ProdEnvAudit/src.tar | grep -iE 'environment\.zig|platform'
./tests/test_windows_platform.py
```

That is the only match in 1743 entries, so the production table this repo's coverage gate reads is
**derived** from the engine's own read sites, not copied from a source table. The derivation is
`gen.py`, the table is `prod-settings-table.zig`, and `check-prod-rows.py` proves the set against the
binary's own name list.

## 2. The derived row set: 118 names

The served binary is the PROMOTION-RULES oracle for the engine actually run. The parity window's phase
0 captured its own name list (2026-11-24T07:59:03Z, `docs/receipts/ParityAB/window.sh`'s
`strings_scan`, image check in the same log line):

```
PREFLIGHT image P sha256:235211ea77ee... expected sha256:235211ea77ee...
PREFLIGHT strings P 116 setting names carried by the served binary
ENVSTR P ENVSTR names 54 carried 53 missing 1
```

The one name the 54-name launcher sets that the binary lacks is `TENSORFOLD_VIDEO_TOKENS`, read by the
vision helper's Python tree. The helper is spawned by the served binary (`zig/src/server/vision.zig:110`,
`python3 -m tensorfold.vision.native_helper`) and production runs vision on, so its reads are settings
of the served engine. A scope check over the helper's modules (`scope-check.txt`) finds exactly two
names outside the binary: `TENSORFOLD_VIDEO_TOKENS` (`qwen_processing.py:263`) and
`TENSORFOLD_VISION_WEIGHTS` (`qwen_cuda.py:76`, also read at `:123`/`:143`). Both are rows.

```
rows: table 118 = binary 116 + helper 2; prod.env 118; verdicts 118; set-equal yes
```

The same check, in the other direction, lists every name read in the served Zig paths that the binary
does **not** carry; none is a served setting:

| name | read site | why it is not a row |
|---|---|---|
| `TF_FLASHNEXT_DUMP` | `zig/src/native/metal.zig:135` | the Metal replay engine's dump folder (macOS) |
| `TF_FLASHNEXT_TP` | `zig/src/families/flashnext/engine.zig:362` | the two-Mac speed-up mode |
| `TF_TP_TRACE`, `TF_TP_LOCAL`, `TF_TP_STATS` | `zig/src/families/flashnext/tp.zig:340-342` | the two-Mac link (Metal pipelines) |
| `TF_CUDA_SEGMENTS` | `zig/src/cli/cuda_main.zig:132` | the nemotron CLI, not the served binary |
| `TF_FLASHNEXT_TEST_SWITCH` | `zig/src/families/flashnext/cuda_engine.zig:373` | a test fixture inside an inline `test` block |

The source side also reads 4 other vision names (`TENSORFOLD_MAX_IMAGES`, `TENSORFOLD_MAX_VIDEOS`,
`TENSORFOLD_IMAGE_TOKENS`, `TENSORFOLD_VISION_WORKSPACE_MIB`), all in the binary already.

## 3. The record

`scripts/qwen38/zig/target/env/prod.env` now states 118 rows: 101 `export` lines and 17 `unset` lines,
in two sections.

- **Section 1, the live launcher (54 rows)**: the values captured from the production container's
  `Config.Env` (`live-env.txt`). These are the rows the container carries.
- **Section 2, the engine's defaults (64 rows)**: every other name the engine can read, at its own
  default taken from the read site cited above the line. A default that is a parseable value is written
  out; a default that only absence can express (a presence test, where any text switches the feature
  on) is `unset`, the coverage gate's second honest form. The 17 `unset` rows are listed in section 5.

One verdict per row, in `register.env`, in a tagged block read by
`check-env-coverage.py --tag prod` (the untagged lines remain the dev arm's and the two runs ignore each
other):

| verdict | rows | meaning here |
|---|---:|---|
| `measured` | 52 | production's shipped launcher values (the launcher header records the zmerge8 arm as the measured one; no per-row cells are kept in this repo) |
| `launcher` | 2 | the boot path supplies the value itself: `TENSORFOLD_CUDA_KERNELS` (the recipe injects `KERNELS_PATH`) and `TF_FLASHNEXT_PRODUCT_STREAMS` (the recipe's `config.sh` computes it) |
| `debt` | 38 | the engine's own default for a tuning lever, unmeasured here |
| `inert` | 19 | examined and not a lever on this serve: diagnostic/log/fault switches, the two-rank paths on a one-rank serve, warm turns off |
| `absent` | 7 | no value is the decision: no API key, no request log, no q4 table, no FP8 overlay, no vision-weights override, the checkpoint's rope, GPU 0 |

Each row's line is preceded by `# <kind>: <reason>.` and `# Cite: <path>:<line>`; the cited file is in
this receipt's `src/` copy and the cited line contains the setting's name.

## 4. Gates, as run

All commands from the repo root.

**Production coverage** (the production table, prod.env, the tagged verdicts, the production launcher's
own name filter):

```
$ python scripts/qwen38/zig/target/env/check-env-coverage.py \
    --table docs/receipts/ProdEnvAudit/prod-settings-table.zig \
    --dev scripts/qwen38/zig/target/env/prod.env \
    --register scripts/qwen38/zig/target/env/register.env \
    --scopes flashnext,cuda,common --passes '^(TENSORFOLD|TF_FLASHNEXT)_' --tag prod
coverage: 118 settings in scope, set 118, missing 0, absent 17, annotations 118, worklist markers 0, passage-lost 0
rc=0
```

(`coverage-prod.txt`.)

**The prod.env citation check** (the check-dev-env.py rule: a cited path within eight lines above every
setting, the file resolving, the cited line naming the setting), plus the row-set and launcher-view
checks:

```
$ python docs/receipts/ProdEnvAudit/check-prod-rows.py
rows: table 118 = binary 116 + helper 2; prod.env 118; verdicts 118; set-equal yes
prod-env: 0 setting(s) without a citation
citations: 118/118 resolve; 118/118 cited lines contain the name
launcher: view 54 = captured 54; values equal yes
rc=0
```

(`rows-check.txt`.)

**The dev arm is unchanged.** The checker gained one option, `--tag`, default empty; without it the
verdict regex is the same object and the output is byte-identical to the HEAD checker on both dev trees:

```
$ diff -u <HEAD checker> <new checker>   # both against work/DevTree, no --tag
coverage: 99 settings in scope, set 99, missing 0, absent 2, annotations 6, worklist markers 0, passage-lost 0
rc=0
diff lines: 0
```

(`dev-neutral.txt`; the same comparison against the r5 served tree `work/QRerun/trees/fp4/src` is also
identical, 95/95 with the register's four stale notes for composition-only rows, rc 1 both sides.)
`check-dev-env.py` reads `dev-env: 0 setting(s) without a citation`, and
`check-env-coverage-selftest.sh` reads `SELFTEST-OK 4`.

**The drift gate** compares only the rows whose `prod` verdict says the container carries them (54), in
both directions. Against the captured live environment wrapped as a `docker inspect` JSON with the
pinned image, it reads:

```
$ python scripts/qwen38/zig/target/env/check-prod-env.py --inspect /tmp/insp.json
prod-env: 117 rows compared (54 carried, 63 pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)
rc=0
```

(`drift-prod.txt`; the skipped row is `TENSORFOLD_API_KEY`, never compared.) The real invocation is the
same command against the container on spark6; the gate still refuses (rc 3) unless the image it reads is
the pinned production image, so a GPU window's environment can never be read as production drift.

**The drift gate can still fail** (`check-prod-env-selftest.sh`, six fixtures over the same captured
environment):

```
DRIFT-SELFTEST real ok [rc 0]
DRIFT-SELFTEST carried-value-differs ok [rc 1, 1 x ^DIFF TF_FLASHNEXT_WINDOW]
DRIFT-SELFTEST pinned-default-differs ok [rc 0]
DRIFT-SELFTEST carried-row-removed ok [rc 1, 1 x ^EXTRA TF_FLASHNEXT_WINDOW]
DRIFT-SELFTEST carried-name-absent ok [rc 1, 1 x ^MISSING TF_FLASHNEXT_WINDOW]
DRIFT-SELFTEST pinned-name-carried ok [rc 1, 1 x ^EXTRA TF_FLASHNEXT_ATTN_MULTI]
SELFTEST-OK 6
```

(`drift-selftest.txt`.) The three failure shapes that matter: a carried value differing (DIFF), a
carried name removed from the container (MISSING), and a name the record pins as a default that the
container carries anyway (EXTRA). A pinned-default value changed in prod.env is informational: rc 0.

## 5. The 17 `unset` rows

These are the only rows not written as a value. Each has its reason on the line above it.

- Presence-tested switches, where any text (including `0`) turns the feature on, so absence is the only
  off state: `TENSORFOLD_REQUEST_LOG` (a path), `TENSORFOLD_VISION_SELFTEST`, `TF_FLASHNEXT_BURST_LOG`,
  `TF_FLASHNEXT_GRAPH_LOG`, `TF_FLASHNEXT_OVERLAP`, `TF_FLASHNEXT_PASS_TIMES`, `TF_FLASHNEXT_POISON_PADS`,
  `TF_FLASHNEXT_PREFILL_DIGEST`.
- No value is the decision: `TENSORFOLD_API_KEY` (no key), `TF_FLASHNEXT_INT4AR_FAST` (no FP8 overlay
  path), `TF_FLASHNEXT_MTP_Q4` (no q4 table path), `TF_FLASHNEXT_YARN_RAMP_POSITIONS` (the checkpoint's
  rope decides), `TENSORFOLD_VISION_WEIGHTS` (the checkpoint's own vision weights), `TF_CUDA_DEVICE`
  (GPU 0).
- Parseable defaults, but the launcher's filter cannot carry the name: `TF_TP_TIMEOUT_S` (a `TF_*` name,
  and the serve is one rank), `TF_FLASHNEXT_EXPERT_SHAPE` and `TF_FLASHNEXT_MTP_TOPK` (null defaults:
  the kernel plan's geometry, the checkpoint's `top_k`).

Every one is recorded with its read site and a `debt`, `inert` or `absent` verdict.

## 6. The drift gate's change, and why it is mechanical

Before: `check-prod-env.py` compared every `TF_*`/`TENSORFOLD_*` name in both directions, because
prod.env was only the 54-name launcher copy. A complete record pins the engine's defaults for the other
rows, and those names cannot be in the container - comparing them would report the record's own content
as drift.

Now: the comparison set is derived from the register's `prod` verdict kinds. `measured`, `launcher` and
image-baked rows are carried and compared in both directions; `debt`, `inert`, `absent`, `raw`,
`candidate` and legacy rows are informational. A row with no `prod` verdict is UNVERDICTED and fails, so
the classification cannot rot separately from the record. There is no second list of names anywhere.

## 7. What is unresolved

Nothing. Every one of the 118 rows states a value (or the honest absence), one verdict and a citation
that resolves to a line naming it. The two vision-helper names are the only rows outside the binary's
116, and they are labelled as helper reads. The seven source-only names in section 2 are excluded with
their read sites and reasons.

## 8. Stale text this change does not own

Two documents outside this task's file list now describe the old 54-row copy; they need re-seating by
their owner:

- `docs/ENV-REGISTER.md`, "The production copy cannot drift": says prod.env is a hand copy and that the
  gate compares every name in both directions; both statements are superseded (section 6).
- `docs/PROMOTION-COMPLIANCE.md`: says prod.env states 54 rows, the production table is not read, and
  worklist item 1 is open; all three are superseded by this receipt.

`scripts/qwen38/README.md` carries the current-state paragraph (it was in this task's file list).

## 9. Files

Changed:

- `scripts/qwen38/zig/target/env/prod.env` - 118 rows, two sections, one verdict and citation each.
- `scripts/qwen38/zig/target/env/register.env` - a tagged `prod` verdict block (118 lines) and a header
  note; the untagged dev lines are untouched.
- `scripts/qwen38/zig/target/env/check-env-coverage.py` - one default-off `--tag` option (untagged
  behaviour byte-identical, `dev-neutral.txt`).
- `scripts/qwen38/zig/target/env/check-prod-env.py` - the kind-driven comparison set (section 6).
- `scripts/qwen38/README.md` - the current-state paragraph.

Added, all under `docs/receipts/ProdEnvAudit/`:

- `RESULT.md` (this file), `provenance.txt`, `provenance-tar.txt`, `scope-check.txt`, `tree-compare.txt`,
  `rows-check.txt`, `coverage-prod.txt`, `coverage-dev.txt`, `dev-neutral.txt`, `drift-prod.txt`,
  `drift-selftest.txt`
- `src/` - the pruned copy of every file a row cites (the 30 MB tar itself stays at
  `work/ProdEnvAudit/src.tar`, gitignored, with its sha256 in `provenance.txt`)
- `gen.py` - the row data and the generator for prod.env, the table, the launcher view and the register
  block; `check-prod-rows.py` - the independent verifier; `check-prod-env-selftest.sh` - the drift
  fixtures; `prod-settings-table.zig`, `prod-launcher.env`, `live-env.txt`, `strings-P.txt`,
  `names-P.txt`, `envstr-P.txt`, `qwen6-start-prod.sh`.

Regenerate after a source or value change:

```
python docs/receipts/ProdEnvAudit/gen.py
python docs/receipts/ProdEnvAudit/check-prod-rows.py
```

`gen.py` refuses to write if any citation does not resolve to a line naming its row, or if the row set
is not the binary's names plus the two helper names.
