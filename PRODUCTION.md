# The production serve's recipe (the target to match or beat)

This branch is what the Qwen3.8 Flash Next serve on spark6 runs today: the engine source its image was built from,
and beside it, under `production/`, how that image is built and launched and what it measures. It is frozen: only
a production hotfix lands here. The work on the modern TensorFold engine is on `main`, and it is finished when it
matches or beats `production/SPEED-TARGET.md` at 1, 2, 4, 6 and 8 streams.

## What is here

| path | what |
|---|---|
| the tree (everything but `production/` and this file) | TensorFold at `5c3e3e2961b6ece724c1979ec4c46d6aeae2f48c`: upstream `db281878d`, the MiaAI recipe's patches 0001-0009, our levers 0010-0028 and the zmerge8 keep set (`27b6700cb`, "c68-shared-cost-levels"), then the one 64 KiB-page boot fix to the native weight upload. 634 commits of history |
| `production/Dockerfile.zmerge8k`, `production/build-zmerge8k.sh` | the image build: the native binary and fatbins rebuilt from this tree with `zig build -Doptimize=fast fatbins install native`, laid over the image `tensorfold-qwen38:zmerge8`, plus a one-line `.clone()` in that image's own Python vision loader |
| `production/qwen6-start-prod.sh` | the launcher, with the serve's whole environment (52 `TENSORFOLD_*` and `TF_FLASHNEXT_*` settings) and the recipe it starts through (`MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold` 1.0.0, `364f21a`, at `~/qwen-zig-prod` on the box) |
| `production/mtp_fp8.py` | builds the FP8 MTP drafter overlay the launcher points `TF_FLASHNEXT_MTP_FP8` at |
| `production/SPEED-TARGET.md` | the serve measured at 1, 2, 4, 6 and 8 streams on 2026-11-10: decode, time to first token, memory. Copied as written: its opening lines speak of the retired `1.2.6` branch it was first kept on |

## Provenance, checked 2026-11-12

- Image on spark6: `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, id `sha256:235211ea77ee...`, built
  2026-10-14, label `ai-engine.src-sha256=e5139fcd8c6101c7`.
- That label is the sha256 of the build's source tar (`e5139fcd8c6101c776d9c600021228d389e648f58a398842498d95c3ebcccecc`).
  The tar was unpacked and compared with this tree at `5c3e3e29`: 1,640 files, 0 differences. So the tree here is
  the source of the serving binary, file for file.
- Serves: checkpoint `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` (`14642741`), 8 streams, bf16 KV,
  262,144-token window (the serve's boot banner).
- The files under `production/` are the box's own copies (the launcher, the Dockerfile and the build script) and
  `main`'s copies of the overlay tool and the target document.
- Not reproducible from this branch alone: the base image `tensorfold-qwen38:zmerge8` (the recipe's Python package
  and vision helper) is no longer on spark6; the serving image itself is.
- The history up to `27b6700cb` was the `main` of the retired Gitea repository `ots/tensorfold-levers124`; a bundle
  of everything that repository held is in `main` under `archive/tensorfold-levers124/`.
