#!/usr/bin/env bash
# Run tensorfold bench-many in the Zig image on spark6 (serve must be stopped). Usage: zprof.sh TAG [PROFILE=0|1] [extra args...]
set -uo pipefail
TAG=$1; PROF=${2:-0}; shift 2 || true
IMG=${IMG:-tensorfold-qwen38:zig-db28187}
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
OUT=~/work/zprof; mkdir -p $OUT
ENVS=(-e TF_FLASHNEXT_PREFILL_TAIL=512 -e TF_FLASHNEXT_YARN=0 -e TF_FLASHNEXT_PRODUCT_STREAMS=2 -e TF_FLASHNEXT_DEPTH=15
      -e TENSORFOLD_MEMORY_RESERVE_GIB=10 -e HF_HUB_OFFLINE=1 -e TENSORFOLD_NO_UPDATE_CHECK=1)
[[ $PROF == 1 ]] && ENVS+=(-e TF_FLASHNEXT_PROFILE=1)
for e in ${XENV:-}; do ENVS+=(-e "$e"); done
docker run --rm --gpus all --cap-add SYS_ADMIN --ipc host --network host --name zprof \
  -v /home/adam/.cache/huggingface:/root/.cache/huggingface:ro -v /home/adam/.cache/tensorfold-qwen38/4144696f21e3:/cache \
  -v $OUT:/out "${ENVS[@]}" $IMG \
  ${WRAP:-} /opt/tensorfold/bin/tensorfold ${CMD:-bench-many} $SNAP --kv-dtype fp8 --context ${CTX:-32768} ${SERVED---served} "$@" 2>&1 | tee $OUT/$TAG.log | grep -v "^info" | tail -120
