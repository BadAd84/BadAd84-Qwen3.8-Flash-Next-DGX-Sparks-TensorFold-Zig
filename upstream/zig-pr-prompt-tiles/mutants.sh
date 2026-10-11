#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0024's byte checks, judged by their exit codes.
# `tensorfold fp8-tiles-check` compares every prompt tile mode with the stock kernel at prompt row counts and runs two
# mutants (the fused form told half the slices; the wide tile told a K of 64 less) where the new kernels run; it exits
# 1 on any DIFFER or a surviving mutant. `tensorfold int4-check` compares the prompt gate/up with int4_kernel and
# exits 1 on any differing pair (no mutant of its own). Lane r2c-fable (~/work/lanes/r2c-fable/out1/tiles-check.log):
# PASS, mutants 15/15 and 10/10 killed, on the lane's first build. Re-run on the clean stack's image:
set -uo pipefail
IMG=${1:-tensorfold-qwen38:zpr3-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold fp8-tiles-check "$SNAP" || exit 1
flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold int4-check "$SNAP"
