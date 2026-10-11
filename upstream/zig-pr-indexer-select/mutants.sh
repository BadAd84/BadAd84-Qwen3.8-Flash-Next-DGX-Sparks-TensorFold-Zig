#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0023's byte check, judged by its exit code. `tensorfold qsa-check`
# compares every fn_qsa_stream kind (s5, cs4) and every fn_qsa_scores tile (0-7) with Triton's _scores / _select at
# prompt blocks and decode windows on random, tie-heavy and special inputs; it exits 1 on any DIFFER. The mutants
# were run on the lane's standalone checks (~/work/lanes/r2a-opus/selcheck.log: six select mutants killed;
# scorescheck.log: the fma-order mutant DIFFER in 8/8). Re-run the in-engine check on the clean stack's image:
set -uo pipefail
IMG=${1:-tensorfold-qwen38:zpr3-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold qsa-check "$SNAP"
