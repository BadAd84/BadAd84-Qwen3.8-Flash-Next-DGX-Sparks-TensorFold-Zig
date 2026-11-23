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
2. **`dev.env` is `prod.env` plus candidates**, applied to names both engines read. Measured by name:
   - **40 rows `prod.env` states and `dev.env` omits. They are not a dev gap:** checked against the dev tree, **0** are
     in its settings table, **1** is read by dev code (`TF_FLASHNEXT_HC_Q12`, plumbing), and **39 appear nowhere in
     the dev tree**. Those 39 are names the newer engine dropped or renamed, so stating them in `dev.env` would
     configure nothing; under the scoped rule they are `retired` on the dev side, with the production engine still
     setting them.
   - **94 rows only `dev.env` states:** candidates on the dev engine. Whether each has a production counterpart is
     unknown until the production table is read; the ones with no production reader are dev-engine additions, not
     candidates.
   - **The 2 overturn rows are resolved per engine, with evidence, and are not violations.**
     `TENSORFOLD_CUDA_KERNELS`: the r5 images bake a captured kernel set, and the dev engine refuses a captured set
     with fp8 KV and with the page pool (`cuda_lanes_load.zig:33,35`), so the dev file states `native`; the register
     already carried `image-baked` and `debt` verdicts for it naming that evidence. `TF_FLASHNEXT_PRODUCT_STREAMS`:
     no read call exists in the dev tree, the recipe's `config.sh` computes it at 5, and production's launcher
     overrides 8; it is a launcher-carried name, not a lever on this serve.
3. **One verdict a row, in the register, with evidence.** Met for every case where the answer is known.
   `check-env-coverage.py` now accepts the rule's seven kinds alongside the legacy `default-ok` and `unreachable`,
   requires an evidence path on the verdict's own line, and exempts `retired`, `raw`, `launcher` and `absent` from
   the table-row staleness test (those kinds exist for names without a row). Written so far: 39 `retired` verdicts
   for production-only names, `launcher` for `TF_FLASHNEXT_PRODUCT_STREAMS`, `raw` for `TF_FLASHNEXT_HC_Q12`, and the
   pre-existing `image-baked`/`debt` pair for `TENSORFOLD_CUDA_KERNELS`. What remains is the dev-only 94, which need
   the production table read before each can be called a candidate or an addition.
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
2. Classify the 94 dev-only rows once the production table is read: each becomes a `candidate` (its production
   counterpart is a default), an addition (production has no such row), or a finding.
3. Convert the remaining legacy annotations (`default-ok`, `unreachable`) to the rule's kinds where the better word
   is `inert` or `absent`; the checker already accepts both vocabularies.
4. For each retired patch, check the upstream name at its absorbing commit against ours and adjust every env row,
   launcher option, driver, register verdict and read site before deleting the patch (the four re-seat retirements
   listed in `docs/UPSTREAM-WATCHLIST.md` are the first batch).
5. Make the repo's launcher copies the source of truth, add the sync gate (repo copy sha against the box's), and
   rewrite the launch test to assert the promoted defaults with explicit off arms.
6. Re-measure or stamp every speed table whose cells predate a promotion.

## What does not change

The served dev tree's coverage gate stays as it is (95 rows, passage-lost 0, zero uncited settings): the dev file is
complete against its own tree. The rule adds the production-side completeness and the promotion mechanics around it;
it does not relax either file.
