# Receipts: the tracked copies of every record the docs and `dev.env` cite

The evidence for the statements in `docs/`, `README.md` and `scripts/qwen38/zig/target/env/dev.env` lived
under `work/`, which `.gitignore` excludes: a fresh clone could not support a single number in the env of
record. This directory is the durable copy. Each file below is a byte copy of the `work/` source at the
2026-11-23 snapshot, verified by `sha256sum` at copy time (source and copy equal), and every citation in
the docs now names `docs/receipts/<path>` at the same relative path; the `work/` path stays in the record
where a sentence needs it (a re-run, a box path).

Sizes: 64 files, about 1.0 MiB. Results, tables and logs only; the source trees and build output are
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
| `docs/receipts/KvTierDedup/RESULT.md` | `work/KvTierDedup/RESULT.md` | `75d9a74bb911b351` | `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierShip/ev2.tgz` | `work/KvTierShip/ev2.tgz` | `d871f5d24c0c13bb` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierShip/RESULT.md` | `work/KvTierShip/RESULT.md` | `35399b30f32cafd5` | `docs/ENV-REGISTER.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierShip/SHAPES.md` | `work/KvTierShip/SHAPES.md` | `5adb687a4987842b` | `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/KvTierW4/RESULT.md` | `work/KvTierW4/RESULT.md` | `dafe2ea2b8267656` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierW5/RESULT.md` | `work/KvTierW5/RESULT.md` | `657e9e51f93674d4` | `scripts/qwen38/README.md` |
| `docs/receipts/KvTierW5/tables.md` | `work/KvTierW5/tables.md` | `2872c7ed37a9b188` | (index only) |
| `docs/receipts/P5Gpu/CLOSED.md` | `work/P5Gpu/CLOSED.md` | `ab53790599920ac5` | `docs/KNOB-COVERAGE.md` |
| `docs/receipts/PartFix/REBASE.md` | `work/PartFix/REBASE.md` | `6004e77ff8308f4b` | `docs/OPEN-PR-COVERAGE.md` |
| `docs/receipts/PatchBisect/RESULT.md` | `work/PatchBisect/RESULT.md` | `4f1a5698ed8313f1` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProseDraft/out.fetched/out/B0a/env.txt` | `work/ProseDraft/out.fetched/out/B0a/env.txt` | `2a7043efe18f2149` | `docs/KNOB-COVERAGE.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProseDraft/POLICY.md` | `work/ProseDraft/POLICY.md` | `96a68754dec63d19` | `docs/ENV-REGISTER.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/ProseDraft/RESULT.md` | `work/ProseDraft/RESULT.md` | `5ff75439aa38b26a` | `docs/ENV-REGISTER.md`, `docs/INT4-PORT.md`, `docs/KNOB-COVERAGE.md`, `docs/KNOB-SCREEN.md`, `scripts/qwen38/README.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/QInt4/RESULT.md` | `work/QInt4/RESULT.md` | `3923bbe5245aa1f9` | `docs/INT4-PORT.md` |
| `docs/receipts/QRerun/box/out/QA/env.txt` | `work/QRerun/box/out/QA/env.txt` | `cc490d5521a449d3` | `docs/ENV-REGISTER.md`, `scripts/qwen38/zig/target/env/dev.env` |
| `docs/receipts/QRerun/window.sh` | `work/QRerun/window.sh` | `66e9edb04a669a0f` | `scripts/qwen38/zig/target/env/dev.env` |
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
| `work/prod`, `work/lanes/rpr/recipe`, model caches under `~/.cache` | trees and weights | other engines' source and model data; never evidence for our numbers. |

## How to use

A citation `docs/receipts/X/Y.md` is byte-identical to `work/X/Y.md` as of this snapshot; line numbers in the
docs match the tracked copy. The three gates in `docs/ENV-REGISTER.md` still need the served tree, which is
re-created (upstream main plus `patches/main-1ece6e6db-r5/apply.sh`) and checked by the manifest sha256 quoted
there, not by a copy of the tree.
