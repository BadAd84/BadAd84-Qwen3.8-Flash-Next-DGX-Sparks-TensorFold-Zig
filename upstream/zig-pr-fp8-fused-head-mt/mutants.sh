#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0018's byte checks. `tensorfold fp8-fused-check` compares the fused
# split-K tiles (depths 4 and 8) with the cluster kernel and runs its own mutant (the fused form told half the slices),
# failing when any call differs or the mutant survives; `tensorfold int4-head-check` compares 32-row head items with
# 16-row items and 1-row calls. Both exit 1 on a failure. Lane w8-opus (its w8-qmmf / w8-head, the same checks with
# more variants): 1,008/1,008 equal, mutant killed on every tile path; 204/204 equal, item-count mutant
# (w8v2-hmut.patch) caught. Re-run on the clean stack's image:
set -euo pipefail
IMG=${1:-tensorfold-qwen38:zpr-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
run() { flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold "$1" "$SNAP"; }
run fp8-fused-check
run int4-head-check
