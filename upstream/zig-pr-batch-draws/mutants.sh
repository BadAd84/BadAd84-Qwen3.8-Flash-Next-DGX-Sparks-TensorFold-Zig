#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0017's byte check. `tensorfold draft-check` compares the batched
# greedy draw with the per-row draw on 360 adversarial cases and exits 1 on any difference. Lane w4-fable: the shipped
# kernel 360/360 EQUAL (exit 0); the mutant image (~/work/lanes/w4-fable/batch-draws-v2-mutant.patch: the four partial
# sums in one accumulator) 23/360 DIFFER (exit 1) = killed. Re-run on the clean stack's image:
set -euo pipefail
IMG=${1:-tensorfold-qwen38:zpr-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
exec flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold draft-check "$SNAP"
