# Receipts: the tracked copies of every record the docs and `dev.env` cite

The evidence for the statements in `docs/`, `README.md` and `scripts/qwen38/zig/target/env/dev.env` lived
under `work/`, which `.gitignore` excludes: a fresh clone could not support a single number in the env of
record. This directory is the durable copy. Each file below is a byte copy of the `work/` source at the
2026-11-23 snapshot, verified by `sha256sum` at copy time (source and copy equal), and every citation in
the docs now names `docs/receipts/<path>` at the same relative path; the `work/` path stays in the record
where a sentence needs it (a re-run, a box path).

Sizes: 162 files, about 4.3 MiB. Results, tables and logs only; the source trees and build output are
listed at the end as deliberately untracked.

| tracked copy | source in the working tree | sha256 (first 16) | cited by |
| --- | --- | --- | --- |
| `docs/receipts/DevVsProd/RESULT.md` | `work/DevVsProd/RESULT.md` | `19acb08c53269039` | `README.md`, `docs/INT4-PORT.md`, `scripts/qwen38/README.md` |
| `docs/receipts/DocAudit/REPORT.md` | `work/DocAudit/REPORT.md` | `5a3466529acbe948` | `AGENTS.md` |
| `docs/receipts/EnvBoot/coverage-vs-served-tree.current.txt` | `work/EnvBoot/coverage-vs-served-tree.current.txt` | `bf88b980de38ebdb` | (index only) |
| `docs/receipts/EnvBoot/predict_env.py` | `work/EnvBoot/predict_env.py` | `10c821f693fe1237` | `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/EnvBoot/RESULT.md` | `work/EnvBoot/RESULT.md` | `f5533e4313f63d47` | `README.md`, `docs/ENV-REGISTER.md`, `docs/INT4-PORT.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/EnvForward/TABLE.md` | `work/EnvForward/TABLE.md` | `0cbe0127cd6a4a1d` | `upstream/recipe-launcher-tf-env/RECORD.md`, `docs/ENV-REGISTER.md` |
| `docs/receipts/EnvServed/absence-probe.txt` | `work/EnvServed/absence-probe.txt` | `c78cd57cd1663362` | `docs/ENV-REGISTER.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/EnvServed/coverage-after.txt` | `work/EnvServed/coverage-after.txt` | `4718645cbc5f6b11` | (index only) |
| `docs/receipts/EnvServed/coverage-before.txt` | `work/EnvServed/coverage-before.txt` | `bf88b980de38ebdb` | (index only) |
| `docs/receipts/EnvServed/dev-env-after.txt` | `work/EnvServed/dev-env-after.txt` | `dff0cf4c09efd6be` | (index only) |
| `docs/receipts/EnvServed/RESULT.md` | `work/EnvServed/RESULT.md` | `505c8642c23b8770` | (index only) |
| `docs/receipts/Fuse0018Fix/GATES.md` | `work/Fuse0018Fix/GATES.md` | `d218c8e57a117c75` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/Fuse0018Fix/RESULT.md` | `work/Fuse0018Fix/RESULT.md` | `5480e09f15efdbbd` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/GapArms/RESULT.md` | `work/GapArms/RESULT.md` | `4452edc5d4399a1e` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/Glm54Review/REPORT.md` | `work/Glm54Review/REPORT.md` | `0cc128437f79c6b7` | `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/Int4Device/RESULT.md` | `work/Int4Device/RESULT.md` | `a185b8d5649ed3df` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Edges/base-images.log` | `work/Int4Edges/out/base-images.log` | `51f8e3470ed86143` | (index only) |
| `docs/receipts/Int4Edges/base-limits.txt` | `work/Int4Edges/out/base-limits.txt` | `adfc43a5a1a98c39` | (index only) |
| `docs/receipts/Int4Edges/base-stale-launches.txt` | `work/Int4Edges/out/base-stale-launches.txt` | `82dff326e86fa87a` | (index only) |
| `docs/receipts/Int4Edges/head-stale-launches.txt` | `work/Int4Edges/out/head-stale-launches.txt` | `82dff326e86fa87a` | (index only) |
| `docs/receipts/Int4Edges/limits-control.md` | `work/Int4Edges/limits-control.md` | `0ed24cec7035f6c0` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Step5Dev/RESULT.md` | `work/Int4Step5Dev/RESULT.md` | `3a11bed36c193f95` | `docs/INT4-PORT.md` |
| `docs/receipts/DevEnvBoot/RESULT.md` | `work/DevEnvBoot/RESULT.md` | `914aaeeb79f627e6` | `scripts/qwen38/zig/target/env/dev.env`, `docs/ENV-REGISTER.md` |
| `docs/receipts/DevEnvBoot/SUMMARY.txt` | `work/DevEnvBoot/out-fetched/out/SUMMARY.txt` | `f6ea645357507545` | `scripts/qwen38/zig/target/env/dev.env`, `docs/ENV-REGISTER.md` |
| `docs/receipts/DevEnvBoot/envdiff.out` | `work/DevEnvBoot/out-fetched/out/DEVENV/envdiff.out` | `26cf8e2a723a624e` | `scripts/qwen38/zig/target/env/dev.env`, `docs/ENV-REGISTER.md` |
| `docs/receipts/DevEnvBoot/selfcheck-line.txt` | `work/DevEnvBoot/out-fetched/out/DEVENV/selfcheck-line.txt` | `82e728698b2ef224` | `scripts/qwen38/zig/target/env/dev.env`, `docs/ENV-REGISTER.md` |
| `docs/receipts/DevEnvBoot/cells.txt` | `work/DevEnvBoot/out-fetched/out/CELLS/cells.txt` | `c60d7a012f9bcf2c` | `scripts/qwen38/zig/target/env/dev.env`, `docs/ENV-REGISTER.md` |
| `docs/receipts/LauncherAB/SUMMARY.txt` | `work/LauncherAB/out-fetched/out/SUMMARY.txt` | `99c9320f231692e9` | `docs/ENV-REGISTER.md`, `upstream/recipe-launcher-tf-env/RECORD.md` |
| `docs/receipts/PagesAudit/RESULT.md` | `work/PagesAudit/RESULT.md` | `8518bd77566621f6` | `scripts/qwen38/README.md` |
| `docs/receipts/DevBootComp/RESULT.md` | `work/DevBootComp/RESULT.md` | `fb2a59d34c1c065e` | `scripts/qwen38/README.md` |
| `docs/receipts/DevBootComp/ev.tgz` | `work/DevBootComp/ev.tgz` | `27d962e8e2894489` | `scripts/qwen38/README.md` |
| `docs/receipts/PagesAudit/SUMMARY.md` | `work/PagesAudit/out.fetched/out/SUMMARY.md` | `e0e32d0d114af555` | `scripts/qwen38/README.md` |
| `docs/receipts/LauncherAB/abenv-verify.txt` | `work/LauncherAB/out-fetched/out/AB/abenv-verify.txt` | `28b60948ab069c64` | `docs/ENV-REGISTER.md`, `upstream/recipe-launcher-tf-env/RECORD.md` |
| `docs/receipts/LauncherAB/envdiff-verify.txt` | `work/LauncherAB/out-fetched/out/AB/envdiff-verify.txt` | `96bb2a49ca1d72d7` | `docs/ENV-REGISTER.md`, `upstream/recipe-launcher-tf-env/RECORD.md` |
| `docs/receipts/LauncherAB/STAGE` | `work/LauncherAB/out-fetched/out/STAGE` | `78811984eff71d15` | `docs/ENV-REGISTER.md`, `upstream/recipe-launcher-tf-env/RECORD.md` |
| `docs/receipts/Int4Step5Dev/exactness-lines.txt` | `work/Int4Step5Dev/out-fetched/exactness-lines.txt` | `bae7ddf52c1fdf60` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Step5Dev/summary.txt` | `work/Int4Step5Dev/out-fetched/summary.txt` | `c399bec7fe158dc3` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Step5Dev/run.log` | `work/Int4Step5Dev/out-fetched/run.log` | `944b177a235f3902` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Edges/stale-diff.txt` | `work/Int4Edges/out/stale-diff.txt` | `e3b0c44298fc1c14` | (index only) |
| `docs/receipts/Int4Respond/RESULT.md` | `work/Int4Respond/RESULT.md` | `d4ffde40926e8db1` | `docs/INT4-PORT.md` |
| `docs/receipts/Int4Window/QUALITY-DEFECT.md` | `work/Int4Window/QUALITY-DEFECT.md` | `4479df43f2cf5d1b` | `README.md`, `docs/INT4-PORT.md` |
| `docs/receipts/KnobScreen/driver.sh` | `work/KnobScreen/driver.sh` | `26ee393a5f2d7505` | `docs/KNOB-SCREEN.md` (pre-fix copy; the live kit is `scripts/qwen38/zig/target/screen/`) |
| `docs/receipts/KnobScreen/RULE.md` | `work/KnobScreen/RULE.md` | `05f1118eaa4abc6c` | `docs/KNOB-SCREEN.md` (pre-fix copy; the live kit is `scripts/qwen38/zig/target/screen/`) |
| `docs/receipts/KnobScreen/sens.py` | `work/KnobScreen/sens.py` | `4527d475c73cc138` | `docs/KNOB-SCREEN.md` (pre-fix copy; the live kit is `scripts/qwen38/zig/target/screen/`) |
| `docs/receipts/KnobScreen/starter.sh` | `work/KnobScreen/starter.sh` | `d358f7cc9f7a77d1` | `docs/KNOB-SCREEN.md` (pre-fix copy; the live kit is `scripts/qwen38/zig/target/screen/`) |
| `docs/receipts/KnobScreen/dry-run-2026-11-23.txt` | `work/KnobScreen/dry/proofs.txt` (box, printed by `driver.sh dry`) | `155c60951cb853d7` | `docs/KNOB-SCREEN.md` |
| `docs/receipts/KnobScreen/preflight-env-2026-11-23.txt` | `work/KnobScreen/out.failed-2026-11-23T1546/preflight/c1/env.txt` | `a15054a0527feec4` | `docs/KNOB-SCREEN.md`, `scripts/qwen38/zig/target/screen/allow-extra.txt` |
| `docs/receipts/KnobScreen/preflight-settings-2026-11-23.txt` | `work/KnobScreen/out.failed-2026-11-23T1546/preflight/c1/settings.txt` | `cf135a0ea74d1b06` | `docs/KNOB-SCREEN.md` |
| `docs/receipts/KnobScreen/coverage-passage-2026-11-23.txt` | the coverage gate's output after the passage fix (`scripts/qwen38/zig/target/env/check-env-coverage-selftest.sh` proves the rule) | `a4b06d2f73885765` | `docs/KNOB-SCREEN.md` |
| `docs/receipts/KnobTest/CLASSIFY.md` | `work/KnobTest/CLASSIFY.md` | `9cb1a5c8a6b17237` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/KnobTest/receipt/w1/boot.md` | `work/KnobTest/receipt/w1/boot.md` | `f61aa2d8a6248771` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/cells.csv` | `work/KnobTest/receipt/w1/cells.csv` | `de26f21204ac548b` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/decode.md` | `work/KnobTest/receipt/w1/decode.md` | `b86c35a8691ee79f` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/exactness.md` | `work/KnobTest/receipt/w1/exactness.md` | `01755fdfe85463a6` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/golden.md` | `work/KnobTest/receipt/w1/golden.md` | `888ed632b0c701b6` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/resume.md` | `work/KnobTest/receipt/w1/resume.md` | `107c98f814d3ad26` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/summary.json` | `work/KnobTest/receipt/w1/summary.json` | `86ce203a87408ed3` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/ttft.csv` | `work/KnobTest/receipt/w1/ttft.csv` | `f245ab84a85a4750` | (index only) |
| `docs/receipts/KnobTest/receipt/w1/ttft.md` | `work/KnobTest/receipt/w1/ttft.md` | `4dceb77e35f159b5` | (index only) |
| `docs/receipts/KnobTest/RESULT.md` | `work/KnobTest/RESULT.md` | `713df8851412821c` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/KnobTest/VERDICTS.md` | `work/KnobTest/VERDICTS.md` | `f96b2cad6ff8af1f` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierDedup/ev/out/new/seed/env.txt` | `work/KvTierDedup/ev/out/new/seed/env.txt` | `55137353817ca766` | `docs/ENV-REGISTER.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierDedup/RESULT.md` | `work/KvTierDedup/RESULT.md` | `04b597f71b7ed166` | `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierShip/ev2.tgz` | `work/KvTierShip/ev2.tgz` | `d871f5d24c0c13bb` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierShip/RESULT.md` | `work/KvTierShip/RESULT.md` | `a5d286b20abbfd43` | `docs/ENV-REGISTER.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierShip/SHAPES.md` | `work/KvTierShip/SHAPES.md` | `ac5597fe4efdf4c3` | `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierW4/RESULT.md` | `work/KvTierW4/RESULT.md` | `720fc3a8a349bdab` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierW5/RESULT.md` | `work/KvTierW5/RESULT.md` | `0a75f4ed82f2e9b9` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierW5/tables.md` | `work/KvTierW5/tables.md` | `f5f767e52ad99a8a` | (index only) |
| `docs/receipts/P5Gpu/CLOSED.md` | `work/P5Gpu/CLOSED.md` | `ab53790599920ac5` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/ParityAB/RESULT.md` | `work/ParityAB/RESULT.md` | `ad45cace3fececa9` | (index only) |
| `docs/receipts/ParityAB/ev.tgz` | `work/ParityAB/ev.tgz` | `b7e4be66df81ae4c` | (index only) |
| `docs/receipts/ParityAB/in/SHA256SUMS` | `work/ParityAB/in/SHA256SUMS` | `cfc847d66f1478d1` | (index only) |
| `docs/receipts/ParityAB/in/argv.py` | `work/ParityAB/in/argv.py` | `729c4d6e9a85d271` | (index only) |
| `docs/receipts/ParityAB/in/boot_env.sh` | `work/ParityAB/in/boot_env.sh` | `66f8ca128cff30d9` | (index only) |
| `docs/receipts/ParityAB/in/check-prod-env.py` | `work/ParityAB/in/check-prod-env.py` | `3b19dad0faf8bd8a` | (index only) |
| `docs/receipts/ParityAB/in/decompose.py` | `work/ParityAB/in/decompose.py` | `a4fdd51550a64b46` | (index only) |
| `docs/receipts/ParityAB/in/dev.env` | `work/ParityAB/in/dev.env` | `6f0f5156c44fa116` | (index only) |
| `docs/receipts/ParityAB/in/doc_target.json` | `work/ParityAB/in/doc_target.json` | `b5818ed597d662cb` | (index only) |
| `docs/receipts/ParityAB/in/envnames.py` | `work/ParityAB/in/envnames.py` | `659c649536fdeecc` | (index only) |
| `docs/receipts/ParityAB/in/flags.sh` | `work/ParityAB/in/flags.sh` | `cb7882b1c2bc73bd` | (index only) |
| `docs/receipts/ParityAB/in/meta.py` | `work/ParityAB/in/meta.py` | `5c2f87ce84405855` | (index only) |
| `docs/receipts/ParityAB/in/prod.env` | `work/ParityAB/in/prod.env` | `11778f8a6902a742` | (index only) |
| `docs/receipts/ParityAB/in/qf_harness.py` | `work/ParityAB/in/qf_harness.py` | `4606732e34f6d2cb` | (index only) |
| `docs/receipts/ParityAB/in/score_cells.py` | `work/ParityAB/in/score_cells.py` | `735b9ffc9ffc7b46` | (index only) |
| `docs/receipts/ParityAB/in/summarise_parity.py` | `work/ParityAB/in/summarise_parity.py` | `58bfaf6b5e20fd23` | (index only) |
| `docs/receipts/ParityAB/in/tfm_decode.py` | `work/ParityAB/in/tfm_decode.py` | `3e535944abdd33b3` | (index only) |
| `docs/receipts/ParityAB/in/tfm_decode_ids.py` | `work/ParityAB/in/tfm_decode_ids.py` | `6b81cf33090a5eef` | (index only) |
| `docs/receipts/ParityAB/in/ttft.py` | `work/ParityAB/in/ttft.py` | `7fd729adb59f40d6` | (index only) |
| `docs/receipts/ParityAB/in/zgold-base-c1.json` | `work/ParityAB/in/zgold-base-c1.json` | `bb7aa058983dd07f` | (index only) |
| `docs/receipts/ParityAB/in/zgold_cmp.py` | `work/ParityAB/in/zgold_cmp.py` | `d76590633cf020ed` | (index only) |
| `docs/receipts/ParityAB/rerun1.levels` | `work/ParityAB/rerun1.levels` | `84f019f9b41583ee` | (index only) |
| `docs/receipts/ParityAB/restored/envcheck.txt` | `work/ParityAB/restored/envcheck.txt` | `f2843c214ee37dc1` | (index only) |
| `docs/receipts/ParityAB/restored/health.json` | `work/ParityAB/restored/health.json` | `d23898b4e1972ec6` | (index only) |
| `docs/receipts/ParityAB/restored/image.txt` | `work/ParityAB/restored/image.txt` | `e52e61777c95e8c9` | (index only) |
| `docs/receipts/ParityAB/restored/prod-inspect.json` | `work/ParityAB/restored/prod-inspect.json` | `05b40001550216b0` | (index only) |
| `docs/receipts/ParityAB/run.log` | `work/ParityAB/run.log` | `44ce609735ce8f4f` | (index only) |
| `docs/receipts/ParityAB/score1.txt` | `work/ParityAB/score1.txt` | `b0b35d5ad3224d47` | (index only) |
| `docs/receipts/ParityAB/score2.txt` | `work/ParityAB/score2.txt` | `fd99f40b1aeb52e4` | (index only) |
| `docs/receipts/ParityAB/tables.md` | `work/ParityAB/tables.md` | `5fd08f1532d40a67` | (index only) |
| `docs/receipts/ParityAB/window.sh` | `work/ParityAB/window.sh` | `e8239d92fb1dadd0` | (index only) |
| `docs/receipts/PartFix/REBASE.md` | `work/PartFix/REBASE.md` | `6004e77ff8308f4b` | `docs/OPEN-PR-COVERAGE.md` |
| `docs/receipts/PatchBisect/RESULT.md` | `work/PatchBisect/RESULT.md` | `4f1a5698ed8313f1` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProdEnvAudit/RESULT.md` | `work/ProdEnvAudit/RESULT.md` | `0f23ad6565b42b2a` | `scripts/qwen38/README.md` |
| `docs/receipts/ProdEnvAudit/check-prod-env-selftest.sh` | `work/ProdEnvAudit/check-prod-env-selftest.sh` | `76a1eba724199923` | `docs/ENV-REGISTER.md` |
| `docs/receipts/ProdEnvAudit/check-prod-rows.py` | `work/ProdEnvAudit/check-prod-rows.py` | `aab7ba16df1104e4` | `scripts/qwen38/README.md` |
| `docs/receipts/ProdEnvAudit/coverage-dev.txt` | `work/ProdEnvAudit/coverage-dev.txt` | `9df1554f028c73a9` | (index only) |
| `docs/receipts/ProdEnvAudit/coverage-prod.txt` | `work/ProdEnvAudit/coverage-prod.txt` | `af4407b5a152a0f2` | (index only) |
| `docs/receipts/ProdEnvAudit/dev-neutral.txt` | `work/ProdEnvAudit/dev-neutral.txt` | `1a6eb131966d6603` | (index only) |
| `docs/receipts/ProdEnvAudit/drift-prod.txt` | `work/ProdEnvAudit/drift-prod.txt` | `5c4e977b84a66caa` | (index only) |
| `docs/receipts/ProdEnvAudit/drift-selftest.txt` | `work/ProdEnvAudit/drift-selftest.txt` | `a24fb2a45bd39371` | (index only) |
| `docs/receipts/ProdEnvAudit/envstr-P.txt` | `work/ProdEnvAudit/envstr-P.txt` | `8a7764cf2f823cab` | (index only) |
| `docs/receipts/ProdEnvAudit/gen.py` | `work/ProdEnvAudit/gen.py` | `d772cf60e314cf5a` | (index only) |
| `docs/receipts/ProdEnvAudit/live-env.txt` | `work/ProdEnvAudit/live-env.txt` | `30e8dc9ac90c9145` | (index only) |
| `docs/receipts/ProdEnvAudit/names-P.txt` | `work/ProdEnvAudit/names-P.txt` | `42f4ff8a6ba0cf9f` | (index only) |
| `docs/receipts/ProdEnvAudit/prod-launcher.env` | `work/ProdEnvAudit/prod-launcher.env` | `b4e85fbe9f8d94e4` | (index only) |
| `docs/receipts/ProdEnvAudit/prod-settings-table.zig` | `work/ProdEnvAudit/prod-settings-table.zig` | `d828a7278389bc49` | `docs/ENV-REGISTER.md`, `scripts/qwen38/README.md` |
| `docs/receipts/ProdEnvAudit/provenance-tar.txt` | `work/ProdEnvAudit/provenance-tar.txt` | `6217fd3943b0b6e9` | (index only) |
| `docs/receipts/ProdEnvAudit/provenance.txt` | `work/ProdEnvAudit/provenance.txt` | `f20f678b8570a894` | (index only) |
| `docs/receipts/ProdEnvAudit/qwen6-start-prod.sh` | `work/ProdEnvAudit/qwen6-start-prod.sh` | `93f1a2077ffedc4d` | (index only) |
| `docs/receipts/ProdEnvAudit/rows-check.txt` | `work/ProdEnvAudit/rows-check.txt` | `72d08eab804d851e` | (index only) |
| `docs/receipts/ProdEnvAudit/scope-check.txt` | `work/ProdEnvAudit/scope-check.txt` | `f36b7c153a518412` | (index only) |
| `docs/receipts/ProdEnvAudit/src/src/tensorfold/vision/qwen_cuda.py` | `work/ProdEnvAudit/src/src/tensorfold/vision/qwen_cuda.py` | `019cc39ff2c22460` | (index only) |
| `docs/receipts/ProdEnvAudit/src/src/tensorfold/vision/qwen_processing.py` | `work/ProdEnvAudit/src/src/tensorfold/vision/qwen_processing.py` | `e27b2128aad77018` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_comm.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_comm.zig` | `58eaf96d3d0ea87c` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_engine.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_engine.zig` | `c83295dcc2ec34c7` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_forward.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_forward.zig` | `85d03c5963539cfa` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_fp8.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_fp8.zig` | `890e070d9a34b3a6` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_int4.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_int4.zig` | `7e619c450d106faf` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_kernels.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_kernels.zig` | `e01e360f25f13685` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_lanes.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_lanes.zig` | `ca55481bd23e6358` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_mirror.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_mirror.zig` | `393f25fe93317123` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_moe_prompt.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_moe_prompt.zig` | `7f74401f0334ac00` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_native.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_native.zig` | `2f72486e978a4dbd` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_ngram_host.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_ngram_host.zig` | `119f3532620ade2a` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_prof.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_prof.zig` | `3ce15637a61b41e6` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_prompt.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_prompt.zig` | `281f9772dbab5c47` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/families/flashnext/cuda_rope.zig` | `work/ProdEnvAudit/src/zig/src/families/flashnext/cuda_rope.zig` | `a63f38b12d23af57` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/native/cuda.zig` | `work/ProdEnvAudit/src/zig/src/native/cuda.zig` | `d73d1048765c53a2` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/server/main.zig` | `work/ProdEnvAudit/src/zig/src/server/main.zig` | `611ec2d0c0fb9d89` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/server/serve.zig` | `work/ProdEnvAudit/src/zig/src/server/serve.zig` | `2fe3d1ff445a2a59` | (index only) |
| `docs/receipts/ProdEnvAudit/src/zig/src/server/vision.zig` | `work/ProdEnvAudit/src/zig/src/server/vision.zig` | `68136236889edbc7` | (index only) |
| `docs/receipts/ProdEnvAudit/strings-P.txt` | `work/ProdEnvAudit/strings-P.txt` | `43dad35b649c015c` | (index only) |
| `docs/receipts/ProdEnvAudit/tree-compare.txt` | `work/ProdEnvAudit/tree-compare.txt` | `f9ad95e49d8e546a` | (index only) |
| `docs/receipts/ProseDraft/out.fetched/out/B0a/env.txt` | `work/ProseDraft/out.fetched/out/B0a/env.txt` | `2a7043efe18f2149` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProseDraft/POLICY.md` | `work/ProseDraft/POLICY.md` | `96a68754dec63d19` | `docs/ENV-REGISTER.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProseDraft/RESULT.md` | `work/ProseDraft/RESULT.md` | `5ff75439aa38b26a` | `docs/ENV-REGISTER.md`, `docs/INT4-PORT.md`, `docs/KNOB-COVERAGE.md`, `docs/KNOB-SCREEN.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/QInt4/RESULT.md` | `work/QInt4/RESULT.md` | `3923bbe5245aa1f9` | `docs/INT4-PORT.md` |
| `docs/receipts/QRerun/box/out/QA/env.txt` | `work/QRerun/box/out/QA/env.txt` | `cc490d5521a449d3` | `docs/ENV-REGISTER.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/QRerun/window.sh` | `work/QRerun/window.sh` | `66e9edb04a669a0f` | `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/RegisterVerdicts/PROOFS.md` | (authored here) | `e1ff175ca6337b25` | `scripts/qwen38/README.md` |
| `docs/receipts/RegisterVerdicts/fixture-missing-path.env` | `work/RegisterVerdicts/fixture-missing-path.env` | `d174eed49434e179` | (index only) |
| `docs/receipts/RegisterVerdicts/fixture-no-citation.env` | `work/RegisterVerdicts/fixture-no-citation.env` | `ddac0b0d12fc3df7` | (index only) |
| `docs/receipts/RoGpu/receipt/cold.md` | `work/RoGpu/receipt/cold.md` | `02e655f3b84f8446` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/SDFix/RESULT.md` | `work/SDFix/RESULT.md` | `d2ddad7d63e7f4a1` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/SeriesFix/box/out/RESULT-BOX.md` | `work/SeriesFix/box/out/RESULT-BOX.md` | `8c2b27ec3194417c` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/SpeedAudit/CORRECTIONS.md` | `work/SpeedAudit/CORRECTIONS.md` | `ddafd4a9a560fbef` | `docs/INT4-PORT.md`, `docs/KNOB-COVERAGE.md` |
| `docs/receipts/SpeedAudit/REPORT-kimi.md` | `work/SpeedAudit/REPORT-kimi.md` | `4898b6eb5c73b7ef` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/upsubmit/PrCopyWindow/pr-body-g.md` | `work/upsubmit/PrCopyWindow/pr-body-g.md` | `74da098aa33a20f9` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/upsubmit/Triage/ngram.md` | `work/upsubmit/Triage/ngram.md` | `498aa8900c583df7` | (index only) |
| `docs/receipts/upsubmit/Triage/prompt.md` | `work/upsubmit/Triage/prompt.md` | `1bdf7587c854ee04` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/upsubmit/Triage/rest.md` | `work/upsubmit/Triage/rest.md` | `d8e12901f9aa923c` | (index only) |

## Already tracked elsewhere

- `docs/knob-receipt-2026-11-20/` is the tracked window-1 to window-3 receipt (boots, cells, ttft, exactness,
  golden, resume, the prod env copy and the analysis scripts). The knob rows cite its `receipt/w1` directly;
  nothing from it is duplicated here.

## Not tracked, and why

| record | size | why not tracked |
| --- | ---: | --- |
| `work/QRerun/trees/fp4/src` | 177 MiB, 12,622 entries | the served source tree: reproducible from upstream main `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` plus the 20 r5 patches, and identified by its manifest sha256 `b3de0046...2cca57` (`docs/ENV-REGISTER.md`). The gates read it; a clone re-creates it. |
| `work/Int4Step5/tree` | 181 MiB, 13,001 entries | the series tree (head `987de0084`), reproducible from its own base plus the int4 series; its manifest sha256 is in `docs/ENV-REGISTER.md`. |
| `work/Fuse0018Fix/box`, `work/KnobTest/box`, `work/KvTierW5/box` and the other `box/` trees | hundreds of MiB | remote build trees and fetched frames; only their `RESULT.md` and `GATES.md` are evidence. |
| `work/int4/bench-*`, `work/target/bench-*`, `work/bench/rigmark/runs/` | per-run JSON and logs | each run is regenerated by its window script; the committed `docs/INT4-PORT.md` and patch RECORDs carry the verdicts and the cells that matter. |
| `work/KnobScreen/out/` | no window yet | the screen has not run: the kit is tracked at `scripts/qwen38/zig/target/screen/`, the failed preflights are preserved on the box, their env and settings checks and the dry-run transcript are tracked above, and the window's own boot records become a receipt when it runs. |
| `work/ProdEnvAudit/src.tar` | 28.6 MiB | the zmerge8 build source, sha256 `e5139fcd...` equal to the image's label; the derived table and 20 cited files are tracked. |
| `work/prod`, `work/lanes/rpr/recipe`, model caches under `~/.cache` | trees and weights | other engines' source and model data; never evidence for our numbers. |

## How to use

A citation `docs/receipts/X/Y.md` is byte-identical to `work/X/Y.md` as of this snapshot; line numbers in the
docs match the tracked copy. The three gates in `docs/ENV-REGISTER.md` still need the served tree, which is
re-created (upstream main plus `patches/main-1ece6e6db-r5/apply.sh`) and checked by the manifest sha256 quoted
there, not by a copy of the tree.
