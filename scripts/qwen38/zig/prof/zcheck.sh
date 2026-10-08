#!/usr/bin/env bash
# zcheck.sh IMAGE CMD [ARGS...]   (spark6; the serve stopped): one `tensorfold CMD SNAPSHOT ARGS` in IMAGE, e.g. the
# kernel checks with their timings (int4-check, fp8-check, mm-check: no weights loaded).
set -uo pipefail
IMG=$1; CMD=$2; shift 2
SNAP=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd
docker run --rm --gpus all --ipc host --network host -v /home/adam/.cache/huggingface:/root/.cache/huggingface:ro \
  -v /home/adam/.cache/tensorfold-qwen38/4144696f21e3:/cache -e HF_HUB_OFFLINE=1 "$IMG" \
  /opt/tensorfold/bin/tensorfold "$CMD" "$SNAP" "$@" 2>&1 | grep -av "^info\|│"
