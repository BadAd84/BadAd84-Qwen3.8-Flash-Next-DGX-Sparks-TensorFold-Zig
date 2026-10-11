#!/usr/bin/env bash
# mutants.sh (spark6, under the GPU lock): patches/0022's byte check, judged by its exit code. `tensorfold hc-check`
# compares the 12-bit copies' kernels with the kernel set's (675 cases) and runs its built-in mutant (the k16 chunks
# reversed in each block): it exits 1 on any DIFFER or when the mutant is never caught. Lane r2b-opus
# (~/work/lanes/r2b-opus/hc-check.log): EQUAL on all 675 cases, the mutant caught in 30 of 36. The engagement mutant
# (projections zero, golden 0/6) was a switch of the lane image only. Re-run on the clean stack's image:
# Review round 1 (2026-10-11), on the fixed stack (~/work/lanes/r1-fix, tf branch `stack`): the round's
# new host tests and a mutant each, judged by exit code (hostmut.py exits 0 only when every one is killed).
python3 ~/work/lanes/r1-fix/hostmut.py q12-stride-unchecked q12-counters-unchecked hc-q12-ignores-act-exact || exit 1
# `hc-check` passes on the fixed stack and fails with each mutant binary (gmutants.json):
bash ~/work/lanes/r1-fix/gpucheck.sh hc-check table-add-append-then-put table-add-free-then-alloc || exit 1
# `boot` passes on the fixed stack and fails with each mutant binary (gmutants.json):
bash ~/work/lanes/r1-fix/gpucheck.sh boot reduce-act-one-off || exit 1
set -uo pipefail
IMG=${1:-tensorfold-qwen38:zpr3-stack}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
flock ~/work/gpu.lock docker run --rm --gpus all --ipc host --network host -v "$HOME/.cache/huggingface:/root/.cache/huggingface:ro" \
  -v "$HOME/.cache/tensorfold-qwen38/4144696f21e3:/cache" -e HF_HUB_OFFLINE=1 "$IMG" /opt/tensorfold/bin/tensorfold hc-check "$SNAP"
