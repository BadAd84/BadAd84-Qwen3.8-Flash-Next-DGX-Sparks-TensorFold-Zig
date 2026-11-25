# Receipts: the tracked copies of every record the docs and `dev.env` cite

The evidence for the statements in `docs/`, `README.md` and `scripts/qwen38/zig/target/env/dev.env` lived
under `work/`, which `.gitignore` excludes: a fresh clone could not support a single number in the env of
record. This directory is the durable copy. Each file below is a byte copy of the `work/` source at the
2026-11-23 snapshot, verified by `sha256sum` at copy time (source and copy equal), and every citation in
the docs now names `docs/receipts/<path>` at the same relative path; the `work/` path stays in the record
where a sentence needs it (a re-run, a box path).

Sizes: 808 files, about 12.3 MiB. Results, tables and logs only; the source trees and build output are
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
| `docs/receipts/ParityGap/DELIVERABLE-A.md` | `work/ParityGap/DELIVERABLE-A.md` | `a69a0dde34785f4a` | (index only) |
| `docs/receipts/ParityGap/DIFF.md` | `work/ParityGap/DIFF.md` | `21a4babbb34c0d43` | (index only) |
| `docs/receipts/ParityGap/PLAN.md` | `work/ParityGap/PLAN.md` | `1bb6a80bf598adcc` | (index only) |
| `docs/receipts/ParityGap/RESULTS-PARTIAL.md` | `work/ParityGap/RESULTS-PARTIAL.md` | `1a1c06da9bdca03c` | (index only) |
| `docs/receipts/ParityGap/RESULTS.md` | `work/ParityGap/RESULTS.md` | `1103eb65da700556` | (index only) |
| `docs/receipts/ParityGap/driver/boot_env2.sh` | `work/ParityGap/driver/boot_env2.sh` | `dfa99e304051eab9` | (index only) |
| `docs/receipts/ParityGap/driver/hash_cmp.py` | `work/ParityGap/driver/hash_cmp.py` | `cd3ec18ab24d0bc3` | (index only) |
| `docs/receipts/ParityGap/driver/rounds.py` | `work/ParityGap/driver/rounds.py` | `a948c7899e646539` | (index only) |
| `docs/receipts/ParityGap/driver/score_arms.py` | `work/ParityGap/driver/score_arms.py` | `4e8ddfd6cd2ee56c` | (index only) |
| `docs/receipts/ParityGap/driver/window2.sh` | `work/ParityGap/driver/window2.sh` | `23b82b24d7fc32a9` | (index only) |
| `docs/receipts/ParityGap/driver/window3.sh` | `work/ParityGap/driver/window3.sh` | `f9fae9ef5204176b` | (index only) |
| `docs/receipts/ParityGap/ev/bootlines-D.txt` | `work/ParityGap/ev/bootlines-D.txt` | `63bff9ef9d129b9c` | (index only) |
| `docs/receipts/ParityGap/ev/bootlines-P.txt` | `work/ParityGap/ev/bootlines-P.txt` | `a781e6d76eef20be` | (index only) |
| `docs/receipts/ParityGap/ev/box-config-dev.sh` | `work/ParityGap/ev/box-config-dev.sh` | `0a17c29fc230b83d` | (index only) |
| `docs/receipts/ParityGap/ev/box-config-prod.sh` | `work/ParityGap/ev/box-config-prod.sh` | `238ff14ee45cf363` | (index only) |
| `docs/receipts/ParityGap/ev/box-launcher-dev.sh` | `work/ParityGap/ev/box-launcher-dev.sh` | `cce62b647331ee4b` | (index only) |
| `docs/receipts/ParityGap/ev/box-launcher-prod.sh` | `work/ParityGap/ev/box-launcher-prod.sh` | `93f1a2077ffedc4d` | (index only) |
| `docs/receipts/ParityGap/ev/box-start-dev.sh` | `work/ParityGap/ev/box-start-dev.sh` | `4f53b1a5090a28a3` | (index only) |
| `docs/receipts/ParityGap/ev/box-start-prod.sh` | `work/ParityGap/ev/box-start-prod.sh` | `5ec3bab4791e6ce9` | (index only) |
| `docs/receipts/ParityGap/ev/cfgdiff.txt` | `work/ParityGap/ev/cfgdiff.txt` | `757da237714b43ee` | (index only) |
| `docs/receipts/ParityGap/ev/env-D-container.txt` | `work/ParityGap/ev/env-D-container.txt` | `fc025735f68b3e1d` | (index only) |
| `docs/receipts/ParityGap/ev/env-P-container.txt` | `work/ParityGap/ev/env-P-container.txt` | `30e8dc9ac90c9145` | (index only) |
| `docs/receipts/ParityGap/ev/envdiff.txt` | `work/ParityGap/ev/envdiff.txt` | `18073d731efa7469` | (index only) |
| `docs/receipts/ParityGap/ev/namecheck.txt` | `work/ParityGap/ev/namecheck.txt` | `5d52c59bdb2a17c5` | (index only) |
| `docs/receipts/ParityGap/ev/screen-hashes.md` | `work/ParityGap/ev/screen-hashes.md` | `338f0322f429ae59` | (index only) |
| `docs/receipts/ParityGap/ev/screen-score.md` | `work/ParityGap/ev/screen-score.md` | `31fdd9dabda7b430` | (index only) |
| `docs/receipts/ParityGap/ev/screen.tgz` | `work/ParityGap/ev/screen.tgz` | `069ac2570a02beff` | (index only) |
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
| `docs/receipts/DecodeProfile/RESULT.md` | (authored here) | `8f1f37c5fd195df5` | (index only) |
| `docs/receipts/DecodeProfile/decode_profile.sh` | `work/DecodeProfile/decode_profile.sh` | `49bbe63736e0f1f5` | (index only) |
| `docs/receipts/DecodeProfile/ev/benchlog-dec1-20261022-095508.phases.txt` | (authored here) | `4d79636b273ef960` | (index only) |
| `docs/receipts/DecodeProfile/ev/nb-dec1-20261022-095508.cuda_gpu_kern_sum.csv` | (authored here) | `d67b4583a2d28172` | (index only) |
| `docs/receipts/DecodeProfile/ev/ncu-s1-kernel-share.txt` | (authored here) | `ad96b804cf6c902c` | (index only) |
| `docs/receipts/DecodeProfile/nsys_sum.py` | `work/DecodeProfile/nsys_sum.py` | `66f52015275aac0a` | (index only) |
| `docs/receipts/DecodeProfile/stage_table.py` | `work/DecodeProfile/stage_table.py` | `4fbb6965571cf2c7` | (index only) |
| `docs/receipts/DecodeProfile/trace_decode.py` | `work/DecodeProfile/trace_decode.py` | `08bfe05a88e6ccd7` | (index only) |
| `docs/receipts/KvDtype/RESULT.md` | `work/KvDtype/RESULT.md` | `f5cd724c6b21aa3e` | (index only) |
| `docs/receipts/KvDtype/replies-tables.md` | (authored here) | `c621d924ad9a77a8` | (index only) |
| `docs/receipts/KvDtype/run.log.excerpt` | (authored here) | `1291ca8c32012166` | (index only) |
| `docs/receipts/KvDtype/speed-tables.md` | (authored here) | `fa8d0366590b5d73` | (index only) |
| `docs/receipts/LeanDebt/CLASSES.md` | (authored here) | `4c52951f54f70288` | (index only) |
| `docs/receipts/ParityDivergence/RESULT.md` | (authored here) | `5ff44055347e5c84` | (index only) |
| `docs/receipts/ParityGap/confirm/hashes.md` | (authored here) | `db409d3421d67814` | (index only) |
| `docs/receipts/ParityGap/confirm/run.log.excerpt` | (authored here) | `affb634ed96f1cdb` | (index only) |
| `docs/receipts/ParityGap/confirm/score.md` | (authored here) | `2595cce94bca093a` | (index only) |
| `docs/receipts/ParityIdentical/INVENTORY.md` | (authored here) | `b9b2b7f6bac1faee` | (index only) |
| `docs/receipts/ParityIdentical/METHOD.md` | (authored here) | `56dcbb0601ee7c7a` | (index only) |
| `docs/receipts/ParityIdentical/RESULT.md` | (authored here) | `1a980b06aec2a306` | (index only) |
| `docs/receipts/ParityIdentical/boot_cell.sh` | (authored here) | `c9cc2976564069a3` | (index only) |
| `docs/receipts/ParityIdentical/flip-rates.txt` | `work/ParityIdentical/flip-rates.txt` | `30a8c09fb6d00cc0` | (index only) |
| `docs/receipts/ParityIdentical/in/analyse.py` | (authored here) | `e4297edf1fc38a7e` | (index only) |
| `docs/receipts/ParityIdentical/in/boot_cell.sh` | (authored here) | `c9cc2976564069a3` | (index only) |
| `docs/receipts/ParityIdentical/in/check-prod-env.py` | (authored here) | `3b19dad0faf8bd8a` | (index only) |
| `docs/receipts/ParityIdentical/in/dev.env` | (authored here) | `6f0f5156c44fa116` | (index only) |
| `docs/receipts/ParityIdentical/in/dist_probe.py` | (authored here) | `7b37866744acd0b0` | (index only) |
| `docs/receipts/ParityIdentical/in/parity_probe.py` | (authored here) | `64b911df6fd42674` | (index only) |
| `docs/receipts/ParityIdentical/in/prod.env` | (authored here) | `11778f8a6902a742` | (index only) |
| `docs/receipts/ParityIdentical/in/prompts/code-1k.txt` | (authored here) | `8de34eed52218de1` | (index only) |
| `docs/receipts/ParityIdentical/in/prompts/code-rec0.txt` | (authored here) | `e6846aa6e6952c67` | (index only) |
| `docs/receipts/ParityIdentical/in/prompts/prose-1k.txt` | (authored here) | `c57749b9ff69a116` | (index only) |
| `docs/receipts/ParityIdentical/in/prompts/prose-8k.txt` | (authored here) | `efbea102b02e6ce0` | (index only) |
| `docs/receipts/ParityIdentical/in/prompts/prose-rec0.txt` | (authored here) | `c37ff9ba576f7e1f` | (index only) |
| `docs/receipts/ParityIdentical/in/qf_harness.py` | (authored here) | `4606732e34f6d2cb` | (index only) |
| `docs/receipts/ParityIdentical/in/recorded-shas.json` | (authored here) | `720702792605654d` | (index only) |
| `docs/receipts/ParityIdentical/in/summarise.py` | (authored here) | `218344dfb1f7b12e` | (index only) |
| `docs/receipts/ParityIdentical/preflight-dryrun.txt` | (authored here) | `bb9fb03f59b4811f` | (index only) |
| `docs/receipts/ParityIdentical/run-queued.log` | (authored here) | `36de75d1a3b48824` | (index only) |
| `docs/receipts/ParityIdentical/window.sh` | (authored here) | `86308f54a6d3da78` | (index only) |
| `docs/receipts/PrefillKernelPort/AB-PLAN.md` | (authored here) | `a50493d0d6ce4ca9` | (index only) |
| `docs/receipts/PrefillKernelPort/MECHANISM.md` | (authored here) | `d1628c12ce532548` | (index only) |
| `docs/receipts/PrefillKernelPort/README.md` | (authored here) | `1457daaede8b58b3` | (index only) |
| `docs/receipts/PrefillKernelPort/driver/boot_env.sh` | (authored here) | `ff3ed47cbebd00a9` | (index only) |
| `docs/receipts/PrefillKernelPort/driver/hash_cmp.py` | (authored here) | `cd3ec18ab24d0bc3` | (index only) |
| `docs/receipts/PrefillKernelPort/driver/rounds.py` | (authored here) | `a948c7899e646539` | (index only) |
| `docs/receipts/PrefillKernelPort/driver/score_pks.py` | (authored here) | `c6113cad80f6f154` | (index only) |
| `docs/receipts/PrefillKernelPort/driver/window.sh` | (authored here) | `a08ca7ba202a0908` | (index only) |
| `docs/receipts/SharedDraftsMain/BUILD-RECEIPT.md` | (authored here) | `ad48b4963d093489` | (index only) |
| `docs/receipts/SharedDraftsMain/Dockerfile` | `work/SharedDraftsMain/Dockerfile` | `d9395845bd639a51` | (index only) |
| `docs/receipts/SharedDraftsMain/EVIDENCE-QUOTES.md` | `work/SharedDraftsMain/EVIDENCE-QUOTES.md` | `af5b3b935f442295` | (index only) |
| `docs/receipts/SharedDraftsMain/INDEX.md` | (authored here) | `98b68adc984f5622` | (index only) |
| `docs/receipts/SharedDraftsMain/PLAN.md` | `work/SharedDraftsMain/PLAN.md` | `c4b1c631f87922c0` | (index only) |
| `docs/receipts/SharedDraftsMain/RESULT.md` | (authored here) | `6528acec10af0979` | (index only) |
| `docs/receipts/SharedDraftsMain/build.sh` | `work/SharedDraftsMain/build.sh` | `684a8d083b970534` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/build_result.py` | (authored here) | `97353d692b4ad59e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/collect.log` | (authored here) | `fe41e4aa9c8bd816` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out-bundle.tgz` | (authored here) | `90d0d80e8d367d6d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/RESULT-collector.md` | (authored here) | `bf4358c4c7033832` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/cell.json` | (authored here) | `e12bf27c0c907553` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/gpu.txt` | (authored here) | `8a7d78fb11ed5027` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/harness.log` | (authored here) | `8d5bfae52905d0c3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/health-end.json` | (authored here) | `76428c08c9e6f1e7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/inspect-boot.json` | (authored here) | `6334bb7c2aa71bb4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/inspect-end.json` | (authored here) | `6334bb7c2aa71bb4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-boot.txt` | (authored here) | `4d5c8ea565a6c370` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p1-after.txt` | (authored here) | `5e9c23bce748c981` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p1-before.txt` | (authored here) | `5ffa3610ca32b8fc` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p2-after.txt` | (authored here) | `536e12d99962951d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p2-before.txt` | (authored here) | `686e45d9035843cb` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p3-after.txt` | (authored here) | `62e8fd90bdca7612` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-c1-p3-before.txt` | (authored here) | `b02915748c40dbdf` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/metrics-end.txt` | (authored here) | `e757e8fea8730f07` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/models-boot.json` | (authored here) | `1fe5e68eb40b2a43` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/models-end.json` | (authored here) | `8301ec443ce54873` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/server-log-boot.txt` | (authored here) | `fbcd2dff4c84eace` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1-run2/server-log-end.txt` | (authored here) | `b38a6a4abcdf2d75` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/cell.json` | (authored here) | `f4c721d29af7047a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/gpu.txt` | (authored here) | `c0b7226f044254d3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/harness.log` | (authored here) | `8cf134e302a29f4b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/health-end.json` | (authored here) | `9ec569fb884840d2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/inspect-boot.json` | (authored here) | `59b81ec00b09be63` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/inspect-end.json` | (authored here) | `59b81ec00b09be63` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-boot.txt` | (authored here) | `61cf7210037059b9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p1-after.txt` | (authored here) | `78bed75c6472e9e0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p1-before.txt` | (authored here) | `961f9afb78f3edb5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p2-after.txt` | (authored here) | `fdf0fd791c3f3d5d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p2-before.txt` | (authored here) | `78bed75c6472e9e0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p3-after.txt` | (authored here) | `155bc904f1a07598` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-c1-p3-before.txt` | (authored here) | `ffe292049b1b69c6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/metrics-end.txt` | (authored here) | `5a096d1fc7a12153` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/models-boot.json` | (authored here) | `53dc353fb298298b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/models-end.json` | (authored here) | `8cc8390578d8b24e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/server-log-boot.txt` | (authored here) | `d31b722dc5376d1e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c1/server-log-end.txt` | (authored here) | `d2f26d2aac653dba` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/cell.json` | (authored here) | `74f13ab07612a212` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/gpu.txt` | (authored here) | `20e5e6b77a4cf550` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/harness.log` | (authored here) | `8718478e0e82d32a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/health-boot.json` | (authored here) | `056ddcef57221f2b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/health-end.json` | (authored here) | `76a2a0d557764c5e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/inspect-boot.json` | (authored here) | `a4fba415e72f350c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/inspect-end.json` | (authored here) | `a4fba415e72f350c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-boot.txt` | (authored here) | `0c00a7c2a4816783` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p1-after.txt` | (authored here) | `0ee8cc54a04dfb50` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p1-before.txt` | (authored here) | `e971529ad7582407` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p2-after.txt` | (authored here) | `3cf5b74e1c54d3d5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p2-before.txt` | (authored here) | `0ee8cc54a04dfb50` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p3-after.txt` | (authored here) | `36af7737ca3a1e81` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-c2-p3-before.txt` | (authored here) | `3cf5b74e1c54d3d5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/metrics-end.txt` | (authored here) | `36af7737ca3a1e81` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/models-boot.json` | (authored here) | `84f9ce262c6df5b0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/models-end.json` | (authored here) | `0c020f8be38f66e1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/server-log-boot.txt` | (authored here) | `3075d5f33993e970` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2-run2/server-log-end.txt` | (authored here) | `131ad661c50f2d34` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/cell.json` | (authored here) | `482cd0dca5e1996f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/gpu.txt` | (authored here) | `ad291423e102ced2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/harness.log` | (authored here) | `f9c8115de9144f01` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/health-end.json` | (authored here) | `d37f6681d5f057d9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/inspect-boot.json` | (authored here) | `cae41fbff0b9a41b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/inspect-end.json` | (authored here) | `cae41fbff0b9a41b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-boot.txt` | (authored here) | `61af8af97d37837f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p1-after.txt` | (authored here) | `ca939ef7bc43740b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p1-before.txt` | (authored here) | `ed9792b0ab04e7cf` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p2-after.txt` | (authored here) | `db70491c90c6f2a5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p2-before.txt` | (authored here) | `ca939ef7bc43740b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p3-after.txt` | (authored here) | `7abc4f94ca10912e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-c2-p3-before.txt` | (authored here) | `db70491c90c6f2a5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/metrics-end.txt` | (authored here) | `368cb1a028b3078f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/models-boot.json` | (authored here) | `cc5700d702b16702` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/models-end.json` | (authored here) | `fd5bd1da9f8c1b43` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/server-log-boot.txt` | (authored here) | `baa8f95807e21123` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c2/server-log-end.txt` | (authored here) | `5ba9eb0f80f55831` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/cell.json` | (authored here) | `052b5bf523bc64b1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/gpu.txt` | (authored here) | `1db3005183f483e0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/harness.log` | (authored here) | `e2f228813d9b5881` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/health-end.json` | (authored here) | `911450572edb082e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/inspect-boot.json` | (authored here) | `b8c0fed07f2f51a5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/inspect-end.json` | (authored here) | `b8c0fed07f2f51a5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-boot.txt` | (authored here) | `d282f292ba3d9e64` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p1-after.txt` | (authored here) | `d9f3ddf91d1c09fd` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p1-before.txt` | (authored here) | `98be15d16c7c45ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p2-after.txt` | (authored here) | `cfef0ed04a71d294` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p2-before.txt` | (authored here) | `d9f3ddf91d1c09fd` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p3-after.txt` | (authored here) | `77b80d5b839f6a9a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-c4-p3-before.txt` | (authored here) | `cfef0ed04a71d294` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/metrics-end.txt` | (authored here) | `77b80d5b839f6a9a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/models-boot.json` | (authored here) | `29b0b6c472ee04b8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/models-end.json` | (authored here) | `781dbef0699cfe32` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/server-log-boot.txt` | (authored here) | `baa8f95807e21123` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4-run2/server-log-end.txt` | (authored here) | `a7e6f7d3150ac176` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/boot.log` | (authored here) | `913c699dba056a49` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/cell.json` | (authored here) | `18d2a829a6a5a95c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/gpu.txt` | (authored here) | `3cc3ae275579d831` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/harness.log` | (authored here) | `2ac85aaf1778f21f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/health-boot.json` | (authored here) | `8039e31c3235e9d4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/health-end.json` | (authored here) | `af78ca738be000c3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/inspect-boot.json` | (authored here) | `24423b6e2830f31b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/inspect-end.json` | (authored here) | `24423b6e2830f31b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-boot.txt` | (authored here) | `1b58e08aaefcbfe0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p1-after.txt` | (authored here) | `ddfd49affb96bc53` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p1-before.txt` | (authored here) | `b7f70db4f919d64d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p2-after.txt` | (authored here) | `8e78b5b81592fee8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p2-before.txt` | (authored here) | `5bc6aa36905b4e96` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p3-after.txt` | (authored here) | `5c4cef723186b909` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-c4-p3-before.txt` | (authored here) | `8e78b5b81592fee8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/metrics-end.txt` | (authored here) | `5c4cef723186b909` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/models-boot.json` | (authored here) | `7e77fd6017ae0e2a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/models-end.json` | (authored here) | `5a63948cce0246a8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/plan.txt` | (authored here) | `29ec70dbeda2c0ce` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/server-log-boot.txt` | (authored here) | `071b856fab79fd79` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c4/server-log-end.txt` | (authored here) | `00137c04d014ce94` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/cell.json` | (authored here) | `484a7237f5436b5a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/gpu.txt` | (authored here) | `25ddb7c8d19fd012` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/harness.log` | (authored here) | `673c7803d1116a21` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/health-end.json` | (authored here) | `8533674b8bc2de17` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/inspect-boot.json` | (authored here) | `34b7db8ceba0b716` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/inspect-end.json` | (authored here) | `34b7db8ceba0b716` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-boot.txt` | (authored here) | `13e514616f8f8a46` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p1-after.txt` | (authored here) | `f7365929e278afed` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p1-before.txt` | (authored here) | `3bc1fbdb20e86db1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p2-after.txt` | (authored here) | `d16f55b4efa3c19b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p2-before.txt` | (authored here) | `f7365929e278afed` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p3-after.txt` | (authored here) | `6a1393aa2fc40b1a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-c8-p3-before.txt` | (authored here) | `b6c7130d72511f60` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/metrics-end.txt` | (authored here) | `5b9a9d75ed9ec384` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/models-boot.json` | (authored here) | `ac91f91529fa1070` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/models-end.json` | (authored here) | `b64f691e7bfb1061` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/server-log-boot.txt` | (authored here) | `b5285d25dac5fdf7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8-run2/server-log-end.txt` | (authored here) | `b289f72325c5b72b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/cell.json` | (authored here) | `a26cacba4a1f2e23` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/gpu.txt` | (authored here) | `85b64270587de2a5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/harness.log` | (authored here) | `7f458aa94c83371b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/health-end.json` | (authored here) | `fabf73076318f174` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/inspect-boot.json` | (authored here) | `11c422078561455b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/inspect-end.json` | (authored here) | `11c422078561455b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-boot.txt` | (authored here) | `f1f554ebd89ec768` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p1-after.txt` | (authored here) | `e11caa4bfa78d365` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p1-before.txt` | (authored here) | `159406ad76dc6f23` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p2-after.txt` | (authored here) | `dbf80c8b6993f413` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p2-before.txt` | (authored here) | `2e4a6cabcf734e3b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p3-after.txt` | (authored here) | `aa5ea6297c72f7c8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-c8-p3-before.txt` | (authored here) | `60f395d6474f65ce` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/metrics-end.txt` | (authored here) | `6f6d01f39609e5f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/models-boot.json` | (authored here) | `669c5d6fdc943dc9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/models-end.json` | (authored here) | `6d53a558db8d4fcf` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/server-log-boot.txt` | (authored here) | `f3fdccc039d4dae3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/c8/server-log-end.txt` | (authored here) | `f1011c8e6cf18f79` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/boot.log` | (authored here) | `71f4e6344ad37be6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/cell.json` | (authored here) | `f3dd08ec881690f9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/env-boot.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/env-end.txt` | (authored here) | `f826829348c7855a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/gpu.txt` | (authored here) | `aa774d07d20ef057` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/harness.log` | (authored here) | `60a90efba8970faa` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/health-end.json` | (authored here) | `85313812fdb7f68c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/inspect-boot.json` | (authored here) | `fbc1fdb24f7455b6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/inspect-end.json` | (authored here) | `fbc1fdb24f7455b6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/metrics-boot.txt` | (authored here) | `525e0b90d81c291d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/metrics-cached-after.txt` | (authored here) | `23a394b25194116f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/metrics-cached-before.txt` | (authored here) | `d99647b9ad7b07aa` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/metrics-end.txt` | (authored here) | `265e167feadf538f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/models-boot.json` | (authored here) | `bd8395b64c942054` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/models-end.json` | (authored here) | `0d01437eed42447b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/server-log-boot.txt` | (authored here) | `5e7dc898e1e3c80b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm0/cached/server-log-end.txt` | (authored here) | `6fec5b31ac0d4250` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/cell.json` | (authored here) | `739fa5c460ae5fd9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/gpu.txt` | (authored here) | `6cd7b7bc3a0a2179` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/harness.log` | (authored here) | `39b9c4b98ee5ecd9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/health-end.json` | (authored here) | `a1b622f7f010c801` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/inspect-boot.json` | (authored here) | `276bd150416fab92` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/inspect-end.json` | (authored here) | `276bd150416fab92` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-boot.txt` | (authored here) | `c0bf2590e83863a1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p1-after.txt` | (authored here) | `59d00181ebcfc91e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p1-before.txt` | (authored here) | `c58b7e7e51438d92` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p2-after.txt` | (authored here) | `a00e60df780bd533` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p2-before.txt` | (authored here) | `eb95018e0c319b19` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p3-after.txt` | (authored here) | `8c7c6eb4e205ae24` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-c1-p3-before.txt` | (authored here) | `a00e60df780bd533` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/metrics-end.txt` | (authored here) | `b3d75ff21f90a35a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/models-boot.json` | (authored here) | `40c04e87b443b089` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/models-end.json` | (authored here) | `c4a13e348a12ef6f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/server-log-boot.txt` | (authored here) | `b599c0d1f5426dfb` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1-run2/server-log-end.txt` | (authored here) | `37d823eddb4c5ec1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/cell.json` | (authored here) | `dd9cf5503cb6019a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/gpu.txt` | (authored here) | `4f4a4432982eccca` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/harness.log` | (authored here) | `2e5208022b08e347` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/health-end.json` | (authored here) | `7f5263d6a77d6d00` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/inspect-boot.json` | (authored here) | `540f8e968853aeb9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/inspect-end.json` | (authored here) | `540f8e968853aeb9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-boot.txt` | (authored here) | `39842ca033fa585b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p1-after.txt` | (authored here) | `dc214c68285102e3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p1-before.txt` | (authored here) | `2eeca198d291a622` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p2-after.txt` | (authored here) | `f99f04da22ae1c1b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p2-before.txt` | (authored here) | `fa16dcf6929768d5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p3-after.txt` | (authored here) | `093a5c843e1ef888` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-c1-p3-before.txt` | (authored here) | `f848978d57c20bc5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/metrics-end.txt` | (authored here) | `e590b6b15efd723b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/models-boot.json` | (authored here) | `dfcdf93dccff8fc4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/models-end.json` | (authored here) | `eeda814457e35413` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/server-log-boot.txt` | (authored here) | `633bffc9f130909d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c1/server-log-end.txt` | (authored here) | `8c3fba7817499c8d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/cell.json` | (authored here) | `95e52e2c7fa6054d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/gpu.txt` | (authored here) | `e7773668bb0372c7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/harness.log` | (authored here) | `237d2801bb78ab4e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/health-end.json` | (authored here) | `616e699ce7eb825e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/inspect-boot.json` | (authored here) | `9c183849aa421e07` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/inspect-end.json` | (authored here) | `9c183849aa421e07` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-boot.txt` | (authored here) | `3e865e31998ffb9c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p1-after.txt` | (authored here) | `943bd61c3a8c7ed8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p1-before.txt` | (authored here) | `b316af689b25a2e1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p2-after.txt` | (authored here) | `c838bc12ca49a33a` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p2-before.txt` | (authored here) | `9e148776f1e1cd8c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p3-after.txt` | (authored here) | `1c500f7a6e114a8d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-c2-p3-before.txt` | (authored here) | `10d109347edeb7f3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/metrics-end.txt` | (authored here) | `1c500f7a6e114a8d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/models-boot.json` | (authored here) | `94231e4f66412d79` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/models-end.json` | (authored here) | `79723a5df3796a67` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/server-log-boot.txt` | (authored here) | `5e7dc898e1e3c80b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2-run2/server-log-end.txt` | (authored here) | `323d1b56c1534e5e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/boot.log` | (authored here) | `8057a367259cdd2e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/cell.json` | (authored here) | `03b61c9e5ef6d729` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/gpu.txt` | (authored here) | `b71000024f96988d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/harness.log` | (authored here) | `88528dba1789c804` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/health-end.json` | (authored here) | `20e9d7d115129391` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/inspect-boot.json` | (authored here) | `24fac1ca77fea411` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/inspect-end.json` | (authored here) | `24fac1ca77fea411` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-boot.txt` | (authored here) | `e9c9604771c4bb39` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p1-after.txt` | (authored here) | `f4a52d92be388276` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p1-before.txt` | (authored here) | `8d0b6cddbb02fa7f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p2-after.txt` | (authored here) | `d1b9e54214ba710d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p2-before.txt` | (authored here) | `bfd4490188c2b443` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p3-after.txt` | (authored here) | `285dbf99cd7d4dbf` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-c2-p3-before.txt` | (authored here) | `d1b9e54214ba710d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/metrics-end.txt` | (authored here) | `63405966e39e9576` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/models-boot.json` | (authored here) | `9a4c3ce1cd6cb66d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/models-end.json` | (authored here) | `b20a5309b7d95827` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/server-log-boot.txt` | (authored here) | `5ec86449b48669e7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c2/server-log-end.txt` | (authored here) | `b095fe58e1ee1ae1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/cell.json` | (authored here) | `b0b41a5986a37b89` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/gpu.txt` | (authored here) | `b99f5b0c932838dc` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/harness.log` | (authored here) | `fbc0dd221d62bb9f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/health-end.json` | (authored here) | `d529a90cbb3710a6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/inspect-boot.json` | (authored here) | `19f2e3041ce0a4d7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/inspect-end.json` | (authored here) | `19f2e3041ce0a4d7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-boot.txt` | (authored here) | `e6c9b397c9267e8b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p1-after.txt` | (authored here) | `76d0ec53658495ca` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p1-before.txt` | (authored here) | `a2e76dde27c28f68` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p2-after.txt` | (authored here) | `55ae86f882057466` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p2-before.txt` | (authored here) | `76d0ec53658495ca` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p3-after.txt` | (authored here) | `b6923c9f2284ba2d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-c4-p3-before.txt` | (authored here) | `3fcf72c144923e05` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/metrics-end.txt` | (authored here) | `a7c46c4a5164048f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/models-boot.json` | (authored here) | `ad9770fcbf8aae45` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/models-end.json` | (authored here) | `1fb1e2692662107e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/server-log-boot.txt` | (authored here) | `30c6a2fda403553c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4-run2/server-log-end.txt` | (authored here) | `96c40cd1ba519f53` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/cell.json` | (authored here) | `b22c4c37ba86bbf2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/gpu.txt` | (authored here) | `cafe2f30dfc49a7e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/harness.log` | (authored here) | `3a47a90408ea46fa` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/health-boot.json` | (authored here) | `ba1822bfdc4d33e9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/health-end.json` | (authored here) | `389be32c5247facc` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/inspect-boot.json` | (authored here) | `1a2130a9c4565d37` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/inspect-end.json` | (authored here) | `1a2130a9c4565d37` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-boot.txt` | (authored here) | `77d13cac520bc891` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p1-after.txt` | (authored here) | `ec091322858f4f42` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p1-before.txt` | (authored here) | `64b271d15203a2a8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p2-after.txt` | (authored here) | `4561bed34d2aff4c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p2-before.txt` | (authored here) | `ec091322858f4f42` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p3-after.txt` | (authored here) | `bd94af0350e3967c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-c4-p3-before.txt` | (authored here) | `4561bed34d2aff4c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/metrics-end.txt` | (authored here) | `bd94af0350e3967c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/models-boot.json` | (authored here) | `2355c14214a13d42` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/models-end.json` | (authored here) | `7eecf1238393af41` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/server-log-boot.txt` | (authored here) | `1da1dcdb92b572bb` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c4/server-log-end.txt` | (authored here) | `568d401d210d7662` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/cell.json` | (authored here) | `86195edca37d7dbf` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/gpu.txt` | (authored here) | `7405ab671d451f22` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/harness.log` | (authored here) | `e6446ea981c413fb` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/health-end.json` | (authored here) | `23c6c4d43d58bcb8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/inspect-boot.json` | (authored here) | `049aaacfb80f57fe` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/inspect-end.json` | (authored here) | `049aaacfb80f57fe` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-boot.txt` | (authored here) | `e8f4a468206093e2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p1-after.txt` | (authored here) | `57feb5b6106d72b2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p1-before.txt` | (authored here) | `3ae14096781ffde8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p2-after.txt` | (authored here) | `a0572226aa55115d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p2-before.txt` | (authored here) | `57feb5b6106d72b2` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p3-after.txt` | (authored here) | `b3f1f7d07990119c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-c8-p3-before.txt` | (authored here) | `a0572226aa55115d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/metrics-end.txt` | (authored here) | `b3f1f7d07990119c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/models-boot.json` | (authored here) | `185a0ec6813678e1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/models-end.json` | (authored here) | `64296d8fd1d6b43c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/server-log-boot.txt` | (authored here) | `baa8f95807e21123` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8-run2/server-log-end.txt` | (authored here) | `edeb9029aa533fa1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/cell.json` | (authored here) | `a4920e83bac3d306` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/gpu.txt` | (authored here) | `f4cf76ec34c55e07` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/harness.log` | (authored here) | `bfe5555e8c682dfa` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/health-end.json` | (authored here) | `b97cc7e51ec66a9f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/inspect-boot.json` | (authored here) | `fab03edf55e0d3dd` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/inspect-end.json` | (authored here) | `fab03edf55e0d3dd` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-boot.txt` | (authored here) | `b7efd64b98158761` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p1-after.txt` | (authored here) | `35603b0875843cac` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p1-before.txt` | (authored here) | `4bd80ce1ff5ab3f4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p2-after.txt` | (authored here) | `624b85ff3d6849c4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p2-before.txt` | (authored here) | `457eb57162b9caf3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p3-after.txt` | (authored here) | `2371af879ca6d4db` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-c8-p3-before.txt` | (authored here) | `624b85ff3d6849c4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/metrics-end.txt` | (authored here) | `2371af879ca6d4db` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/models-boot.json` | (authored here) | `3931496c5bd96904` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/models-end.json` | (authored here) | `7e6a29508a692665` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/server-log-boot.txt` | (authored here) | `baa8f95807e21123` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/c8/server-log-end.txt` | (authored here) | `32c05a0dc51ed37d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/cell.json` | (authored here) | `a7475850b62fee82` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/gpu.txt` | (authored here) | `d9c367dfc163189b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/harness.log` | (authored here) | `71818d9fd229f2f7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/health-boot.json` | (authored here) | `11752b479325c8f1` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/health-end.json` | (authored here) | `3f1e0f159a37b894` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/inspect-boot.json` | (authored here) | `c6e7dc60ec5045f0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/inspect-end.json` | (authored here) | `c6e7dc60ec5045f0` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/metrics-boot.txt` | (authored here) | `a6434f3aa9bf3048` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/metrics-cached-after.txt` | (authored here) | `1411b660121a49fe` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/metrics-cached-before.txt` | (authored here) | `f94133b1dae8107f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/metrics-end.txt` | (authored here) | `5150a0752c2b0eca` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/models-boot.json` | (authored here) | `59559fe4c52c85b3` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/models-end.json` | (authored here) | `3ecc490c4ee01338` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/server-log-boot.txt` | (authored here) | `5e7dc898e1e3c80b` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/arm1/cached/server-log-end.txt` | (authored here) | `538d43c8861f24c9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/binary-sha256.txt` | (authored here) | `e4f9000e411d76f9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/build.log` | (authored here) | `60e13e02492c92b4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/ckpt-hashes.txt` | (authored here) | `bfa1e334b96516b7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/ckpt-index.txt` | (authored here) | `01ddd7540bc15858` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/ckpt-ls.txt` | (authored here) | `8a5f7e737b3af1fe` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/ckpt-ref.txt` | (authored here) | `9ed41ae21e578525` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/ckpt-size.txt` | (authored here) | `b6878b1cd2f85802` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/image-version.txt` | (authored here) | `67b44e0991fcd978` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/img-id.txt` | (authored here) | `0c81d31f907cc90f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/img.json` | (authored here) | `eb87c73c6f174bac` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/prod-envcheck.txt` | (authored here) | `70e271c2ff1dee38` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/prod-health.json` | (authored here) | `b34a1dc080e037db` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/prod-image.txt` | (authored here) | `e52e61777c95e8c9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/prod-inspect.json` | (authored here) | `b3133aec2635f633` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/phase0/strings.txt` | (authored here) | `f20802e079682b84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/rerun1.levels` | (authored here) | `3726e64f89d2ccc6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/restored/envcheck.txt` | (authored here) | `70e271c2ff1dee38` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/restored/health.json` | (authored here) | `da7befbe91dd803c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/restored/image.txt` | (authored here) | `e52e61777c95e8c9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/restored/prod-inspect.json` | (authored here) | `08b5fa6699393f12` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/run.log` | (authored here) | `e8438b4e55d292a8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/score.json` | (authored here) | `3abdbcddf714a02e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/score1.txt` | (authored here) | `a8d919f18e92b5d5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/score2.txt` | (authored here) | `83c00c38502efce8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/boot.log` | (authored here) | `641167e205fe1623` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/cell.json` | (authored here) | `5416670fc1b888e6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/cmd-boot.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/cmd-end.json` | (authored here) | `bcf6eac0e0b380ec` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/env-boot.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/env-end.txt` | (authored here) | `c12073c0e229716e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/gpu.txt` | (authored here) | `35db15578702be3d` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/harness.log` | (authored here) | `d6395037ac601218` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/health-boot.json` | (authored here) | `070164d60cd6bb59` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/health-end.json` | (authored here) | `b30207ab1c06cb6f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/image-id-boot.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/image-id-end.txt` | (authored here) | `26ae59aed433961e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/inspect-boot.json` | (authored here) | `e9dbacb7b8d74ba5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/inspect-end.json` | (authored here) | `e9dbacb7b8d74ba5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/metrics-boot.txt` | (authored here) | `7370bb1d7c6a0142` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/metrics-end.txt` | (authored here) | `9f7f57a4b9bc4e77` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/metrics-smoke-after.txt` | (authored here) | `23a576f03504aa65` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/metrics-smoke-before.txt` | (authored here) | `d9d2a0db44fe1f36` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/models-boot.json` | (authored here) | `76692f138e3b1dac` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/models-end.json` | (authored here) | `4d640515c4852416` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/plan.txt` | (authored here) | `b4cabd6d68388f84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/server-log-boot.txt` | (authored here) | `18b92fa70abf66fd` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/smoke/server-log-end.txt` | (authored here) | `329d703897adbc70` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/out/tables.md` | (authored here) | `8ad1c74bb120d2be` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/binary-sha256.txt` | (authored here) | `e4f9000e411d76f9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/build.log` | (authored here) | `60e13e02492c92b4` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/ckpt-hashes.txt` | (authored here) | `bfa1e334b96516b7` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/ckpt-index.txt` | (authored here) | `01ddd7540bc15858` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/ckpt-ls.txt` | (authored here) | `8a5f7e737b3af1fe` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/ckpt-ref.txt` | (authored here) | `9ed41ae21e578525` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/ckpt-size.txt` | (authored here) | `b6878b1cd2f85802` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/image-version.txt` | (authored here) | `67b44e0991fcd978` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/img-id.txt` | (authored here) | `0c81d31f907cc90f` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/img.json` | (authored here) | `eb87c73c6f174bac` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/prod-envcheck.txt` | (authored here) | `70e271c2ff1dee38` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/prod-health.json` | (authored here) | `b34a1dc080e037db` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/prod-image.txt` | (authored here) | `e52e61777c95e8c9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/prod-inspect.json` | (authored here) | `b3133aec2635f633` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/phase0/strings.txt` | (authored here) | `f20802e079682b84` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/probe_counters.py` | (authored here) | `6414d6e97c015e90` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/probe_streams.py` | (authored here) | `237de3802dd29652` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/rerun1.levels` | (authored here) | `3726e64f89d2ccc6` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/restored/envcheck.txt` | (authored here) | `70e271c2ff1dee38` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/restored/health.json` | (authored here) | `da7befbe91dd803c` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/restored/image.txt` | (authored here) | `e52e61777c95e8c9` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/restored/prod-inspect.json` | (authored here) | `08b5fa6699393f12` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/run.log` | (authored here) | `e8438b4e55d292a8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/score.json` | (authored here) | `3abdbcddf714a02e` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/score1.txt` | (authored here) | `a8d919f18e92b5d5` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/score2.txt` | (authored here) | `83c00c38502efce8` | (index only) |
| `docs/receipts/SharedDraftsMain/evidence/tables.md` | (authored here) | `8ad1c74bb120d2be` | (index only) |
| `docs/receipts/SharedDraftsMain/sd-boot.sh` | `work/SharedDraftsMain/sd-boot.sh` | `358ab7c7389aa695` | (index only) |
| `docs/receipts/SharedDraftsMain/sd-collect.sh` | `work/SharedDraftsMain/sd-collect.sh` | `f90ef06fbf2e75e9` | (index only) |
| `docs/receipts/SharedDraftsMain/sd-window.sh` | `work/SharedDraftsMain/sd-window.sh` | `f93b245b95924bec` | (index only) |
| `docs/receipts/SharedDraftsMain/sd_harness.py` | `work/SharedDraftsMain/sd_harness.py` | `0e3a36ad82ee16a3` | (index only) |
| `docs/receipts/SharedDraftsMain/sd_report.py` | `work/SharedDraftsMain/sd_report.py` | `0e06ae544119556d` | (index only) |
| `docs/receipts/SharedDraftsMain/sd_score.py` | `work/SharedDraftsMain/sd_score.py` | `4c8182888c2750e3` | (index only) |
| `docs/receipts/SharedDraftsMain/sd_tables.py` | `work/SharedDraftsMain/sd_tables.py` | `ea76e329995aa378` | (index only) |

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
