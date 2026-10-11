#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0022's byte check, judged by its exit code. `tensorfold hc-check`
# compares the 12-bit copies' kernels with the kernel set's (675 cases) and runs its built-in mutant (the k16 chunks
# reversed in each block): it exits 1 on any DIFFER or when the mutant is never caught. Lane r2b-opus
# (~/work/lanes/r2b-opus/hc-check.log): EQUAL on all 675 cases, the mutant caught in 30 of 36. The engagement mutant
# (projections zero, golden 0/6) was a switch of the lane image only. Re-run on the clean stack's image:
set -uo pipefail
IMG=${1:-tensorfold-qwen38:zpr3-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold hc-check "$SNAP"
