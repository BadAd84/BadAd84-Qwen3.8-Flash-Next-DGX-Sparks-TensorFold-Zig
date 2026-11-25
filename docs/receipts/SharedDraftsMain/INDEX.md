# Receipt index: issue #4803, clean-main TF_FLASHNEXT_SHARED_DRAFTS A/B

| file | what it is |
| --- | --- |
| `PLAN.md` | the declared method, written and placed on spark6 before the first boot: arms, cells, counters, commands, limits |
| `BUILD-RECEIPT.md` | the image: upstream sha, tree, set-up toolchain, exact build log lines, image id, binary sha; the checkpoint identity and why it is the one main serves |
| `EVIDENCE-QUOTES.md` | the source lines this work cites (the lever, the chain defaults, the counters, the checkpoint in main's docs and receipts) |
| `Dockerfile`, `build.sh` | the exact build inputs for `tensorfold-qwen38:main-9a38b1f7b` |
| `sd-boot.sh` | the one launcher both arms use (`TF_FLASHNEXT_SHARED_DRAFTS` set from the arm; nothing else differs) |
| `sd-window.sh` | the window driver: GPU lock, alternating fresh boots, scoring, rerun rule, restore trap |
| `sd_harness.py` | the client: greedy, thinking off, 512 tokens, upstream's own SSE reader and evidence helpers |
| `sd_score.py`, `sd_tables.py` | the scorer and the markdown tables (hash equality, ratios, counters, cached control) |
| `sd_report.py` | assembles `RESULT.md` from the stored evidence |
| `sd-collect.sh` | on spark6: on the window's `WINDOW-DONE`, tars the evidence bundle and generates `RESULT.md` |
| `RESULT.md` | THE DELIVERABLE: the concurrency table (both arms' decode and TTFT, S1/S0), the draft and acceptance counters with their source, the cached two-stream control, the noise statement, the identity and the restore proof |
| `evidence/` | the raw evidence the RESULT is built from: `score.json`, `score1.txt`, `score2.txt`, `tables.md`, `run.log`, `collect.log`, `rerun1.levels`, `out/` (all 19 per-cell directories, uncompressed), `out-bundle.tgz`, `phase0/` (build log, checkpoint hashes), `restored/` (restore proof), and the report/table generators |

Remote artefacts on spark6 (`~/work/SharedDraftsMain/`): `out/` (the per-cell evidence tree), `out-bundle.tgz`
(the same tree, tarred), `out/run.log` (the window log with the `RESTORED` and `WINDOW-DONE` markers),
`RESULT.md` (generated from the evidence by `sd_report.py`), `build/build.log` (the image build).

`RESULT.md` here is the hand-assembled receipt from `evidence/build_result.py` reading `evidence/score.json`;
the window's own `sd_report.py` output is kept in `evidence/out/RESULT-collector.md` for comparison. Both read
the same `score.json`, so the numbers agree.

No repository commit was made for this work; this directory is untracked.
Local (this directory) and on spark6 `~/work/SharedDraftsMain/` are the same artefacts.
