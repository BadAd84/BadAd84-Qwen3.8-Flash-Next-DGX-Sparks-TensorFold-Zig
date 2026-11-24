# Promotion compliance: where this repo stands against `PROMOTION-RULES.md`

The rule file at the repo root is the owning text for env-row and launcher-option promotion. This page is the
measured state against it, written 2026-11-23, so the gaps are worked rather than rediscovered.

## What the files are today

| file | rows | what it currently is |
|---|---:|---|
| `scripts/qwen38/zig/target/env/dev.env` | 112 exports + 2 unsets | the dev arm, complete against the SERVED DEV tree's table (gate `coverage: 99 settings in scope, set 99, missing 0, absent 2, passage-lost 0`) |
| `scripts/qwen38/zig/target/env/prod.env` | 118 (101 exports + 17 unsets) | the production engine's complete record: 54 launcher values, 63 pinned engine defaults with read sites, 1 never compared (`TENSORFOLD_API_KEY`); the derived table and its provenance are in `docs/receipts/ProdEnvAudit/` |

## The rule's tests, against those files

1. **Every row set in both files.** Met for `prod.env`: 118 rows, read as `coverage: 118 settings in scope, set
   118, missing 0, absent 17, annotations 118, worklist markers 0, passage-lost 0` against the production table,
   and `citations: 118/118 resolve; 118/118 cited lines contain the name` (`check-prod-rows.py`). The
   production tree carries no settings table (its build source tar has zero `environment.zig`), so the table is
   derived from the served binary's 116 names plus the vision helper's two; the derivation and the source's
   sha256 are in `docs/receipts/ProdEnvAudit/`.
2. **`dev.env` is `prod.env` plus candidates**, applied to names both engines read. Measured by name against
   the 118-row production set: **22 names both files state**; **96 production rows `dev.env` omits** (the ones
   the dev engine does not read are `retired` on the dev side, with the production engine still setting them);
   **92 dev rows have no production row**, so they are additions on the dev engine, not candidates waiting on a
   table that does not exist.
   - **The 2 overturn rows are resolved per engine, with evidence, and are not violations.**
     `TENSORFOLD_CUDA_KERNELS`: the r5 images bake a captured kernel set, and the dev engine refuses a captured set
     with fp8 KV and with the page pool (`cuda_lanes_load.zig:33,35`), so the dev file states `native`; the register
     already carried `image-baked` and `debt` verdicts for it naming that evidence. `TF_FLASHNEXT_PRODUCT_STREAMS`:
     no read call exists in the dev tree, the recipe's `config.sh` computes it at 5, and production's launcher
     overrides 8; it is a launcher-carried name, not a lever on this serve.
3. **One verdict a row, in the register, with evidence.** Met for every case where the answer is known.
   `check-env-coverage.py` now accepts the rule's seven kinds alongside the legacy `default-ok` and `unreachable`,
   requires an evidence path on the verdict's own line, and exempts `retired`, `raw`, `launcher` and `absent` from
   table-row staleness test (those kinds exist for names without a row). The production table is read now: 118
   `prod` verdicts (52 `measured`, 2 `launcher`, 38 `debt`, 19 `inert`, 7 `absent`), all cited, and the 92
   dev-only names are additions. What remains for this test is the legacy `default-ok`/`unreachable` conversion.
4. **Launcher promotion mechanics.** Met. The four launchers were edited on the box, and two gates hold the
   copies: `check-launcher-sync.py --check-local` proves each repo launcher's working-tree, index and HEAD
   copies are one file, `--check-box` reads the box (the dev launcher against the repo copy, the production
   launcher against the `production` branch and against the dev launcher, and both recipe copies' filter lines
   against the recorded line: 5 checks, 0 drifted), and `check-launcher-contract.py` proves every promoted
   `dev.env` row in a documented state (`launcher 14, engine-default 79, env-carried 21`) with an explicit off
   arm for all 80 switch names (`0 problem(s)`). `TF_FLASHNEXT_PRODUCT_STREAMS` is the one launcher-wins row
   (`dev.env` 5, the launcher 8) and the contract prints it as a NOTE.
5. **Tables that predate a promotion are marked.** The dev speed tables predate the launcher widening and the
   tier's default, and their headers cite the environment they ran in rather than a promotion stamp. The stamp
   belongs on each table when the promotions land.

## Worklist, in order

1. Write the per-row register entry for each of the 92 dev-only additions where the row does not carry one.
2. Convert the remaining legacy annotations (`default-ok`, `unreachable`) to the rule's kinds where the better
   word is `inert` or `absent`; the checker already accepts both vocabularies.
3. For each retired patch, check the upstream name at its absorbing commit against ours and adjust every env
   row, launcher option, driver, register verdict and read site before deleting the patch (the four re-seat
   retirements listed in `docs/UPSTREAM-WATCHLIST.md` are the first batch).
4. Re-measure or stamp every speed table whose cells predate a promotion.

## What does not change

The served dev tree's coverage gate stays as it is (99 rows in scope, set 99, passage-lost 0, zero uncited
settings): the dev file is complete against its own tree. The rule adds the production-side completeness and
the promotion mechanics around it; it does not relax either file.
