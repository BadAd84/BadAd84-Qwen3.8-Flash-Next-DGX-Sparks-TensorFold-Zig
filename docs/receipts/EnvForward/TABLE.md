# EnvForward: does widening the launcher filter change the flashnext serve?

Subject: the environment-filter one line of the served recipe's `start.sh`, which today forwards only
`^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=`, and the 26 bare `TF_*` names `dev.env` states that therefore never reach
the container. This file answers one question before any widening is measured or posted: **is widening provably
behaviour-neutral for the flashnext TP=1 serve on spark6, name by name, or which names need an `unset`/`export`
change?**

- Served tree: `work/QRerun/trees/fp4/src/zig/src` (the r5 tree the recipe image builds).
- File analysed: `scripts/qwen38/zig/target/env/dev.env`, the working-tree copy with
  `sha256 b0da076a53632d48da3196c3c5f1f9e23512b65f65c3ed7f59f1991188aa9dee` (290 lines). Its committed blob at HEAD is
  `77a504388c2c700bcda8d91d5f3d7bf158a002c9` (`git log -1 --format='%H %cI'` output: `2026-11-23T18:53:26Z`). Another
  lane is editing this file, so every line number below is the one at the sha above.
- Read-only analysis. No boot, no compile, no box access, no git commit, no edit to `dev.env`.
- Deliverable: this file and `PROPOSED.diff` (empty, see section 5).

## 0. Counts and verdict

| count | value |
|---|---|
| bare `TF_*` statements in `dev.env` (name not `TF_FLASHNEXT_*`) | **27**: 26 `export` lines plus 1 `unset` (`TF_ROCE_GID_INDEX`, line 185) |
| exports | **26** (matches the figure `work/DevEnvBoot/RESULT.md` records) |
| EQUAL | **11 statements**: 10 exports plus the bare `unset` (absence preserved) |
| INERT | **16 exports**: 14 read only by the `qwen3_5` family's CUDA code, 1 (`TF_QWEN35_CHUNK_SOLO`) likewise, 1 (`TF_HY4_MEM_FLOOR_GIB`) with no reader and no table row at all |
| DERIVED | **0** |
| DIFFERS | **0** |

**Verdict: widening is behaviour-neutral for the flashnext TP=1 serve on every one of the 26 stated exports and on
the one bare `unset`. No `dev.env` line needs to change for the widening to be safe, so `PROPOSED.diff` is empty.**
Ten exports state a value textually identical to the default absence yields (one of them, `TF_QMMF_HALF_BELOW`, is
read on the served path at load); sixteen exports are read only in a family or file the served engine never enters.
The boot A/B (widened against unwidened: container env diff, window self-check, fixed-prompt replies) is still the
measurement; this table is the precondition, not the receipt.

## 1. The exact set

Enumerated with `grep -nE '^[[:space:]]*(export|unset|declare -x)[[:space:]]+TF_' scripts/qwen38/zig/target/env/dev.env`
and counted with `grep -cE '^export TF_(?!FLASHNEXT_)' -P ...` (26). Both `unset` lines the file carries are
`TF_ROCE_GID_INDEX` (185, bare) and `TF_FLASHNEXT_KV_PAGE_TEST` (247, already inside the forwarded namespace). No
line exports two names, so the set is complete at 27 statements.

## 2. The absence path every row is judged against

All of these are the served tree's own code, not a re-implementation:

- `environment.read(T, name, default)` is `value(T, name, sys.getenv(name), default)` (`platform/environment.zig:413-415`).
- `environment.value` returns `default` when the parse yields null: `(try checked(name, raw)) orelse return default`
  (`platform/environment.zig:395-398`).
- `parse` returns null for unset **and** for blank, because `blank_default` defaults to true
  (`platform/environment.zig:18`) and only rows that set it false are refused when blank (the sole such row is
  `TF_FLASHNEXT_BATCH_DRAWS`, `:42`). So for every row in this table, blank equals unset.
- `environment.path` returns null for unset or blank (`platform/environment.zig:424-427`).
- `environment.device(flag, raw)` returns the flag, else the parsed ordinal, else 0 (`platform/environment.zig:449-452`).
- `flags` overrides exist for `--device`, `--segments` and `--carveout` (`native/cuda.zig:221-222`,
  `cli/cuda_main.zig:215`). A flag, when given, wins over both a delivered value and absence, so the
  delivered-versus-absent comparison for those three rows does not depend on whether the launcher passes it.

The served family is **flashnext**, whose engine declares `model_type = "qwen4_exp"`
(`families/flashnext/cuda_lanes.zig:30`) and is its own registry entry, listed beside `qwen35.native` and
`qwen35.native_moe` in `native/cuda_families.zig:17`. Startup validation for this serve is
`environment.checkScope(.flashnext, ...)` only (`families/flashnext/env_validate.zig:7`, called from
`families/flashnext/cuda_lanes_load.zig:11`, `cuda_prompt_main.zig:10`, `cuda_compare_main.zig:122`,
`cuda_learn_main.zig:142`); no file in the tree calls `checkScope(.cuda)` or `checkScope(.common)`, and
`environment.refusal` has no non-test caller. So none of these 27 statements is validated at boot, and each is parsed
only if its reader runs. Every stated text is accepted by its own row in any case (word `main`, flags `0`/`1`,
`libnccl.so.2` as a control-free path, ordinals inside their bounds, `1792` as a positive MiB, `96`/`15`/`4096` as
sizes, `10` as a size; blanks parse as null).

Two report surfaces could in principle show a delivered default, and neither does:

- The profile line (`server/profile_line.zig:18-33`) prints only entries whose `differs()` is true. Of the 26 names,
  only `TF_CACHE_EVICT` is a registered switch (`core/profile.zig:8`, row at `:144`), and its row sets
  `report_values = &.{"decayed_resume"}` (`:144`), so `main` and absence both print nothing.
- The window self-check and the boot line read `TF_FLASHNEXT_*` names only, which are already forwarded and unchanged
  by the widening.

## 3. The table

Column "reader" is the line that consumes the name, with the absence path in the next column. `dev.env` line numbers
are from the sha above. The class is the claim the row proves: EQUAL means the explicit text and absence produce the
same parsed value (a claim that holds whatever the reachability); INERT means the served family never reads it (a
stronger claim where it applies, and the only claim where the value is not the default).

| # | name | dev.env | reader (file:line) | absence yields | class | what widening does |
|---:|---|---|---|---|---|---|
| 1 | `TF_CACHE_EVICT` | 107 `main` | `core/prompt_cache_decay.zig:13` (`fromEnv`) via `core/profile.zig:234-236` -> `:250-255` -> `:226-231`; row `core/profile.zig:144` with `stable` unset (`:99`); read by the prompt store at `core/prompt_cache.zig:150` | no env -> `resolve` returns the row's `stable`, which is null -> `fromText(null)` (`core/prompt_cache_decay.zig:8-10`) -> `.main` | EQUAL | `main` -> `.main`; same eviction order. The served family is in the row's list (`core/profile.zig:141,144`). The profile line stays silent because only `decayed_resume` is reported. |
| 2 | `TF_STARTUP_RECEIPT` | 109 `0` | `server/main.zig:142` `read(bool, "TF_STARTUP_RECEIPT", false)` | false (`environment.zig:395-398`, `413-415`) | EQUAL | `0` -> flag parse (`environment.zig:328-333`) -> false. Receipts stay off. |
| 3 | `TF_SHARED_PRICE_LOG` | 111 `0` | `core/lanes/price_log.zig:9` (`name` at `:5`), reached at `core/lanes/shared_round.zig:105` | false | EQUAL | `0` -> false. No price line is printed. |
| 4 | `TF_NCCL_LIB` | 133 `libnccl.so.2` | `cuda/nccl.zig:79-81` `path(...) orelse "libnccl.so.2"` | the same literal | EQUAL | the same library name. The name is parsed on the tensor-parallel path (`fabric/tp/config.zig:120`) and opened there (`cuda/tp_group.zig:35`); the stated value equals that path's own fallback, so whether or not the path runs, nothing changes. |
| 5 | `TF_CUDA_DEVICE` | 135 `0` | `native/cuda_device.zig:68-77` (`setting`, default 0) at `native/cuda.zig:221`; `cli/cuda_main.zig:327-329`; `environment.zig:449-452` | 0 | EQUAL | ordinal 0 either way. A `--device` flag would win in both worlds, so it cannot create a difference. |
| 6 | `TF_CUDA_SEGMENTS` | 137 `1` | `native/cuda_device.zig:68-77` (default 1) at `native/cuda.zig:222`; `cli/cuda_main.zig:232` `orelse 1` | 1 | EQUAL | one prompt chunk a call either way. A `--segments` flag would win in both worlds. |
| 7 | `TF_CUDA_CARVEOUT` | 139 `0` | `cuda/carveout.zig:37-39`: `parse` then `wanted = flag or on == "1"` | null -> `wanted` false -> null (off) | EQUAL | off. The MIB is not read while off (`:39` returns before `:41`). |
| 8 | `TF_CUDA_CARVEOUT_MIB` | 141 `1792` | `cuda/carveout.zig:41-45`, with `default_bytes = 1792 << 20` at `:14` | 1792 MiB | EQUAL | the same size if the carveout is ever turned on. Not consulted today (row 7 is off). |
| 9 | `TF_MTP_DRAFTS` | 143 `3` | `families/qwen3_5/cuda_mtp.zig:122` (`default_depth`) | that family's own default, unread here | INERT | the name arrives and is read by nothing: 0 references to `TF_MTP_DRAFTS` in `families/flashnext` or either flashnext host, and the `qwen3_5` CUDA reader file is a different engine's (registry `native/cuda_families.zig:17`). The served drafter depth is `TF_FLASHNEXT_DEPTH`, already forwardable. |
| 10 | `TF_DSPINE_WINDOW` | 145 blank | `families/qwen3_5/cuda_dspine_config.zig:21` (`value(..., raw, 0)`) and `:16` (`parseRaw`); presence at `families/qwen3_5/cuda_sm110_modes.zig:26` | 0 / unset (its own rules) | INERT | 0 references in the flashnext family or hosts. Blank parses as null (`environment.zig:18`, `301-303`), but the whole path is the `qwen3_5` family's. |
| 11 | `TF_DRAFT_NODES` | 147 `15` | `core/lanes/draft_tree.zig:86`, `default_nodes = 15` at `:14` | 15 nodes | INERT | 15 equals the default anyway, and the only caller of the walker that reads it is `families/qwen3_5/cuda_draft_tree.zig:14`. Every file naming `draft_tree` is that file, `core/lanes/lanes.zig:44` (re-export) or `families/qwen3_5/*`; `families/flashnext` has 0 references. |
| 12 | `TF_QMMF_HALF_BELOW` | 149 `96` | `cuda/qmmf.zig:121` `half_below_default = 96`, read at `:123-124` from `Lane.load` (`:211`, `:258`), used at `:352`, `:400`; the flashnext family loads that lane itself (`families/flashnext/cuda_batch_kernels.zig:120` calls `cuda.qmmf.Lane.load`, and `cuda.qmmf` is `cuda/root.zig:38`; also used at `families/flashnext/cuda_projection.zig:12,46`) | 96 | EQUAL | the same half-tile threshold at the same block count. This row is read on the served path at load, so the equality is load-bearing. |
| 13 | `TF_HY4_MEM_FLOOR_GIB` | 151 `10` | none in the served tree: 0 hits under `zig/src`, and no row in `platform/environment.zig` | nothing reads it; no value to compare | INERT | the name arrives and is read by nothing. The only reader anywhere in the repo is an older tree's `families/hy4_flash/cuda_model.zig:227` (default 10), whose family is not in this tree (`docs/ENV-REGISTER.md:204`). |
| 14 | `TF_QWEN_KEEP_LATE` | 155 `0` | `families/qwen3_5/cuda_cache.zig:25` `read(bool, ..., false)`; presence at `cuda_sm110_modes.zig:35` | false | INERT | 0 references in the flashnext family or hosts. (Value equals its default anyway.) |
| 15 | `TF_QWEN_KV_PAGE_TEST` | 157 blank | `families/qwen3_5/cuda_cache.zig:75` `read(u64, ..., 0)`; presence at `cuda_sm110_modes.zig:34` | 0 | INERT | 0 references in the flashnext family or hosts. Blank is a non-null `""` for that `Process.get` presence test, but the test is `qwen3_5` code. |
| 16 | `TF_COST_KEY_TRACE` | 159 `0` | `families/qwen3_5/cuda_cost_adapter.zig:42` | false | INERT | 0 references in the flashnext family or hosts. |
| 17 | `TF_TIMING` | 161 `0` | `families/qwen3_5/cuda_draft.zig:175,553`; `cuda_mtp.zig:163,477`; `cuda_round_timing.zig:12` | false | INERT | 0 references in the flashnext family or hosts. |
| 18 | `TF_NO_TREES` | 163 `0` | `families/qwen3_5/cuda_draft.zig:444`; `cuda_draft_tree.zig:14`; presence at `cuda_sm110_modes.zig:36` | false | INERT | 0 references in the flashnext family or hosts. Its presence masks `TF_DRAFT_NODES` only inside `environment.refusal` (`:503`), which has no non-test caller and which would check `.flashnext` only here. |
| 19 | `TF_MTP_TREES` | 165 `0` | `families/qwen3_5/cuda_mtp.zig:121` | false | INERT | 0 references in the flashnext family or hosts. |
| 20 | `TF_MTP_BATCH` | 167 `1` | `families/qwen3_5/cuda_mtp.zig:124` | true | INERT | 0 references in the flashnext family or hosts. |
| 21 | `TF_QWEN_POOL_LOG` | 169 `0` | `families/qwen3_5/cuda_pages.zig:197` | false | INERT | 0 references in the flashnext family or hosts. flashnext has its own `cuda_pages.zig`, which does not name this variable. |
| 22 | `TF_Q27_POCKET_OFF` | 171 blank | `families/qwen3_5/cuda_pocket.zig:121` `environment.path(...)` | null (off) | INERT | 0 references in the flashnext family or hosts. flashnext's own `cuda_pocket.zig` does not name this variable. Blank is null via `blank_default` (`environment.zig:18`, `424-427`). |
| 23 | `TF_Q27_TAIL` | 173 blank | `families/qwen3_5/cuda_train.zig:251` `read(u64, ..., 1)` | 1 | INERT | 0 references in the flashnext family or hosts. flashnext's own `cuda_train.zig` does not name this variable. |
| 24 | `TF_Q27_GEMM` | 175 blank | `families/qwen3_5/cuda_train_ops.zig:55` `read(?u64, ..., null)` | null (not narrow) | INERT | 0 references in the flashnext family or hosts. |
| 25 | `TF_PROMPT_INTERMEDIATE` | 179 `0` | `native/cuda_snaps.zig:35` `read(bool, ..., false)` via `native/cuda.zig:18`; the flashnext engine declares `snap_intermediate` (`families/flashnext/cuda_lanes.zig:40`), so the guard is on this path | false, which zeroes `rules.intermediate` | EQUAL | `0` -> false -> the same zeroing. Any other value would have been a DIFFERS; this one is not. |
| 26 | `TF_ROCE_GID_INDEX` | 185 `unset` | `cuda/roce.zig:255` presence test `getenv(...) != null`, read at `cuda/roce_verbs.zig:148` | absent -> the table is searched | EQUAL (absence preserved) | `unset` removes the name before the launcher's `env | grep`, so no widening can deliver it and the presence test stays false (the table search) exactly as today. The test sits on the tensor-parallel exchange path (`cuda/roce.zig:49` is its function); the statement is safe on its own mechanism whether or not that path runs. |
| 27 | `TF_QWEN35_CHUNK_SOLO` | 187 `4096` | `families/qwen3_5/cuda_solo.zig:15` (`solo_chunk.rows(name, limits)`), reader `core/lanes/solo_chunk.zig:16` | that family's busy chunk | INERT | 0 references in the flashnext family or hosts. Flash Next's solo chunk is `TF_FLASHNEXT_CHUNK_SOLO` (`families/flashnext/cuda_chunk.zig:22-24`, `29-31`), parsed by `solo_chunk.parse` and not by `rows(name, ...)`. |

Row-by-row sum: 27 statements, 11 EQUAL (rows 1-8, 12, 25, 26), 16 INERT (rows 9-11, 13-24, 27), 0 DERIVED,
0 DIFFERS.

### Why the INERT rows cannot be reached

Three checkable facts, each run over the whole served tree:

1. `grep -rnE 'qwen35|qwen3_5' families/flashnext native/flashnext_host.zig native/flashnext_batch_host.zig` -> **0**.
   The served family cannot name the `qwen3_5` modules at all, so it cannot call a reader that lives in them.
2. `grep -o '"NAME"'` for each of the 16 names over `families/flashnext` plus the two hosts -> **0 for every name**.
   No file on the served path mentions the variable, so no path can parse it.
3. The reader files are the `qwen3_5` family's CUDA files (`families/qwen3_5/cuda_mtp.zig`, `cuda_cache.zig`,
   `cuda_cost_adapter.zig`, `cuda_draft.zig`, `cuda_pages.zig`, `cuda_pocket.zig`, `cuda_train.zig`,
   `cuda_train_ops.zig`, `cuda_solo.zig`, `cuda_dspine_config.zig`, `cuda_sm110_modes.zig`), and the one core reader
   (`core/lanes/draft_tree.zig`) has exactly one caller of its walker, `families/qwen3_5/cuda_draft_tree.zig:14`
   (`grep -rn 'walker.nodes('` over the tree returns that one line). The registry lists `flashnext.native` and
   `qwen35.native` as separate engines (`native/cuda_families.zig:17`), and one serve opens one engine.

The same-named modules in `families/flashnext` (`cuda_mtp.zig`, `cuda_pages.zig`, `cuda_pocket.zig`, `cuda_train.zig`)
are its own files: a relative `@import("cuda_mtp.zig")` inside `families/flashnext` resolves to
`families/flashnext/cuda_mtp.zig`, not to the `qwen3_5` one. None of them names any of these variables (fact 2).

## 4. The eight names the container already gets from the recipe

`scripts/qwen38/zig/target/screen/allow-extra.txt` lists the eight names the recipe's `scripts/config.sh` supplies on
every boot, which `dev.env` does not state. All eight already match today's filter (`TF_FLASHNEXT_` or `TENSORFOLD_`),
so the widening does not change them; they are recorded here so the register can state them. Lines 12-19 of that file:

| name | value | config.sh source line (as recorded there) |
|---|---|---|
| `TF_FLASHNEXT_SAMPLE_CAND` | 1 | `config.sh:116 ${TF_FLASHNEXT_SAMPLE_CAND:-1}` |
| `TF_FLASHNEXT_HOST_DRAW_THREADS` | 7 | `config.sh:118 ${TF_FLASHNEXT_HOST_DRAW_THREADS:-7}` |
| `TF_FLASHNEXT_PROMPT_HC2` | 1 | `config.sh:130 ${TF_FLASHNEXT_PROMPT_HC2:-1}` |
| `TF_FLASHNEXT_PROMPT_EXPERT_TILE_ROWS` | 256 | `config.sh:132 ${TF_FLASHNEXT_PROMPT_EXPERT_TILE_ROWS:-256}` |
| `TF_FLASHNEXT_PRODUCT_STREAMS` | 5 | `config.sh:144 ${TF_FLASHNEXT_PRODUCT_STREAMS:-5}` |
| `TENSORFOLD_MAX_IMAGES` | 50 | `config.sh:160 ${TENSORFOLD_MAX_IMAGES:-50}` |
| `TENSORFOLD_IMAGE_TOKENS` | 16384 | `config.sh:162 ${TENSORFOLD_IMAGE_TOKENS:-16384}` |
| `TENSORFOLD_VISION_WORKSPACE_MIB` | 2048 | `config.sh:164 ${TENSORFOLD_VISION_WORKSPACE_MIB:-2048}` |

The measured boot carried all eight (`work/DevEnvBoot/out-fetched/out/DEVENV/envdiff.txt`, `BEYOND-DEVENV` rows:
`TF_FLASHNEXT_PRODUCT_STREAMS=8` there is the window's own override of the recipe's 5, stated in the launcher's
block at `work/KnobScreen/box-snapshot/qwen6-start.sh:57`: a launcher-block value, not a filter question).

## 5. The launcher change assumed

One line, in the recipe's `start.sh`:

```
- done < <(env | grep -E '^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=' || true)
+ done < <(env | grep -E '^(TENSORFOLD|TF_)[A-Z0-9_]+=' || true)
```

Provenance and the copies that carry it (`upstream/recipe-launcher-tf-env/RECORD.md:3-14`): upstream
`MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold` at commit
`20e15e41f2f514a0d287710f4665ee1b5009ba41`, file `start.sh` at line 173; the same line is carried by the two
`start-nsys-ours*.sh` copies in that tree (ours, not upstream's) and by our deployed launcher `~/qwen-zig/start.sh:172`
on spark6, four files, one line each. The surrounding loop (the `while read` that appends `-e NAME=value` and the
`done < <(env | grep ...)` line replaced above) is reproduced from the launcher at `docs/ENV-REGISTER.md:45-57`;
the recipe itself is not on this box. `TF_FLASHNEXT` is itself a `TF_` name, so the wider class covers both prefixes
the filter already passes; nothing that matches today stops matching.

`PROPOSED.diff` is empty (0 bytes) because the verdict is that no `dev.env` line changes: the widened filter makes
the 26 names explicit at their own defaults, delivers one name that nothing reads (`TF_HY4_MEM_FLOOR_GIB`), and
cannot deliver the one that must stay absent (row 26 is already an `unset`). Against a copy of `dev.env`,
`git apply --check --allow-empty PROPOSED.diff` exits **0**. The flag is required: a zero-hunk input makes plain
`git apply --check` refuse with `error: No valid patches in input (allow with "--allow-empty")` and exit **128**,
measured. That refusal is about the empty patch, not about the file it would touch (the copy was byte-identical
after the check).

## 6. What this proof is, and what it is not

- It is a static, cited analysis of the served tree at the sha above, plus the measured container environment and
  launcher snapshot from `work/DevEnvBoot`. Every EQUAL row is a value comparison against the exact absence
  expression; every INERT row is a family-boundary absence of the variable and of the module that holds its reader.
- It is **not** a runtime trace. The boundary is proven by what the code can name, not by a boot. The measurement
  that follows is the A/B already specified in `upstream/recipe-launcher-tf-env/RECORD.md`: the same image, widened
  against unwidened, container environment differing only by these names, the window self-check equal, and
  fixed-prompt replies identical.
- The widened filter forwards the union of bare `TF_*` in the launching shell, which is these 26 plus anything a
  future window block adds. The launcher's own block in the box snapshot exports only `TF_FLASHNEXT_*`
  (`work/KnobScreen/box-snapshot/qwen6-start.sh:45-61`); the measured container's beyond-`dev.env` rows are all
  `TENSORFOLD_` or `TF_FLASHNEXT_` (`work/DevEnvBoot/out-fetched/out/DEVENV/envdiff.txt`, consistent with the filter),
  and `dev.env` measured 74 equal plus 26 not forwardable (`work/DevEnvBoot/RESULT.md` section 2). The recipe's
  `config.sh` extras are the eight `TF_FLASHNEXT_`/`TENSORFOLD_` names above. Any bare `TF_*` added later needs the
  same three checks before it is called safe.
- `TF_HY4_MEM_FLOOR_GIB` will now arrive in the container and be read by nothing. That is the register's fact to
  keep (`docs/ENV-REGISTER.md:204` already says the family is not in this tree), not a widening defect.
- There is no DERIVED row: every absence path on this list is a literal (`0`, `1`, `false`, `96`, `1792` MiB,
  `libnccl.so.2`, `15`) or a policy text whose null maps to `.main`. Nothing here depends on a runtime-computed or
  clamped window on the served path. The one clamp in the set (`TF_MTP_DRAFTS` to the drafter's window) is in a
  family the serve never opens.

## 7. Reproduction

Run from the repo root, with the served tree at `work/QRerun/trees/fp4/src/zig/src`:

```
sha256sum scripts/qwen38/zig/target/env/dev.env            # b0da076a...
grep -nE '^[[:space:]]*(export|unset|declare -x)[[:space:]]+TF_' scripts/qwen38/zig/target/env/dev.env
grep -cE '^export TF_(?!FLASHNEXT_)' -P scripts/qwen38/zig/target/env/dev.env   # 26
for n in TF_CACHE_EVICT ... TF_QWEN35_CHUNK_SOLO; do
  grep -rn "\"$n\"" work/QRerun/trees/fp4/src/zig/src | grep -v _test.zig
done
grep -rn 'qwen35\|qwen3_5' work/QRerun/trees/fp4/src/zig/src/families/flashnext \
  work/QRerun/trees/fp4/src/zig/src/native/flashnext_host.zig \
  work/QRerun/trees/fp4/src/zig/src/native/flashnext_batch_host.zig | wc -l    # 0
grep -rn 'walker.nodes(\|draft_tree.nodes(' work/QRerun/trees/fp4/src/zig/src   # one line, qwen3_5
```

## Appendix: the reader lines, quoted

`core/prompt_cache_decay.zig:8-10,13` `fromText` maps only `decayed_resume` to the opt-in and everything else to
`.main`; `:13` reads `profile.get(.TF_CACHE_EVICT)`. `core/profile.zig:226-231` `resolve` returns the environment
text when present and the row's `stable` otherwise; `:99` gives `stable` a null default and the row at `:144` sets no
`stable`. `cuda/nccl.zig:81` is the literal `orelse "libnccl.so.2"`. `cuda/carveout.zig:37-45` is the carveout's
`wanted`/`default_bytes` logic. `cuda/qmmf.zig:121` is `half_below_default = 96` and `:258` its only read.
`server/main.zig:142`, `core/lanes/price_log.zig:9`, `native/cuda_snaps.zig:35`, `native/cuda_device.zig:68-77`,
`environment.zig:395-398,413-415` are the remaining EQUAL absence paths. `cuda/roce.zig:255` is the presence test the
`unset` keeps false. The INERT reader lines are those cited in the table, each in `families/qwen3_5/` except
`core/lanes/draft_tree.zig:86`.
