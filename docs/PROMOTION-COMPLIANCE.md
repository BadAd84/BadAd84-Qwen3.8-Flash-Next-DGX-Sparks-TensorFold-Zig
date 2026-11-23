# Promotion compliance: where this repo stands against `PROMOTION-RULES.md`

The rule file at the repo root is the owning text for env-row and launcher-option promotion. This page is the
measured state against it, written 2026-11-23, so the gaps are worked rather than rediscovered.

## What the files are today

| file | rows | what it currently is |
|---|---:|---|
| `scripts/qwen38/zig/target/env/dev.env` | 108 exports + 2 unsets | the dev arm, complete against the SERVED DEV tree's table (95 rows on the fp4 tree, gate `coverage: 95 set, 95 ... passage-lost 0`) |
| `scripts/qwen38/zig/target/env/prod.env` | 54 | a hand copy of the running production container's launcher environment, captured 2026-11-23 |

## The rule's tests, against those files

1. **Every row set in both files.** Not met for `prod.env`: the production engine's table is not the dev tree's
   (different base and patch set), and its source is not in this repo. The production image is built by
   `production/Dockerfile.zmerge8k` with `SRCIMG=tensorfold-qwen38:zmerge8`, so its engine table lives in that
   image's source stage. Completing `prod.env` means reading that tree's `zig/src/platform/environment.zig`,
   then stating every row at the production launcher's value or at the engine default written down.
2. **`dev.env` is `prod.env` plus candidates.** Not met. Measured by name:
   - **40 rows `prod.env` states and `dev.env` omits** (for example `TF_FLASHNEXT_COPY_MISS`, `COPY_RAMP`,
     `MULTI_LRU`, `NGRAM_THREADS`, `TF_FLASHNEXT_MTP_FP8`, `TF_FLASHNEXT_PREFILL_ROWS`, `PROMPT_HEAD_SKIP`,
     `QSA_SELECT`, `SOLO_MAX`, `YARN`, `TENSORFOLD_PROMPT_CACHE_WHOLE`). A dev boot therefore drops settings the
     production launcher sets and runs the image ENV or the engine default instead, which is the drift the rule
     names.
   - **94 rows only `dev.env` states.** Allowed only where `prod.env` keeps the same row at the engine default;
     until the production table is read, that cannot be shown row by row.
   - **2 rows `dev.env` overturns that `prod.env` sets:** `TENSORFOLD_CUDA_KERNELS` (production launcher
     `/opt/tensorfold/share/tensorfold/cuda/sm121`, dev `native`) and `TF_FLASHNEXT_PRODUCT_STREAMS`
     (production `8`, dev `5`). Under the rule each is a finding, not a test.
3. **One verdict a row, in the register, with evidence.** Not met in the rule's vocabulary. The register annotates
   rows, but the six verdicts (`measured`, `inert`, `debt`, `raw`, `launcher`, `absent`, `candidate`) and their
   evidence lines are not yet the register's form; two rows carry annotations rather than a verdict.
4. **Launcher promotion mechanics.** The four launchers were edited on the box (the recipe's `start.sh`, its two
   nsys copies, `~/qwen-zig/start.sh`); the repo already holds copies at `scripts/qwen38/qwen-start.sh` and
   `scripts/qwen38/zig/qwen6-start.sh`, but there is **no sync gate** comparing repo copies against the box, and no
   launch test asserting promoted defaults. Both are required by the rule and neither exists yet.
5. **Tables that predate a promotion are marked.** The dev speed tables predate the launcher widening and the
   tier's default, and their headers cite the environment they ran in rather than a promotion stamp. The stamp
   belongs on each table when the promotions land.

## Worklist, in order

1. Read the production engine's table from `tensorfold-qwen38:zmerge8`'s source stage, extend `prod.env` to every
   row at its launcher value or the written-down engine default, and gate it with the production drift check.
2. Reconcile `dev.env` to `prod.env` plus candidates: for each of the 94 dev-only rows either state it in
   `prod.env` at the engine default (if the measurement only raises a default) or record it as a finding; resolve
   the two overturn rows by measurement or by demoting them from the dev arm.
3. Rewrite the register's verdicts to the six kinds, one evidence path per line, and fail the gate on a row with
   none.
4. Make the repo's launcher copies the source of truth, add the sync gate (repo copy sha against the box's), and
   rewrite the launch test to assert the promoted defaults with explicit off arms.
5. Re-measure or stamp every speed table whose cells predate a promotion.

## What does not change

The served dev tree's coverage gate stays as it is (95 rows, passage-lost 0, zero uncited settings): the dev file is
complete against its own tree. The rule adds the production-side completeness and the promotion mechanics around it;
it does not relax either file.
