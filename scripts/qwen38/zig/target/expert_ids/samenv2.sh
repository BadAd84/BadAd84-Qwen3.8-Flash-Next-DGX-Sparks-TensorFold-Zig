#!/usr/bin/env bash
# samenv2.sh - samenv.sh again for production with VISION=0 (its launcher defaults to vision, and its helper refuses
# the nvidia checkpoint's vision tower), our repeats interleaved. Was: samenv.sh - both engines on OUR checkpoint (nvidia FP4, top-10): production's binary through its own launcher and
# measured env (no FP8 drafter overlay, which is built for the INT4 checkpoint) against our 14-patch series (v16) with
# its drafter in BF16 (the series default) and, as an extra arm, MXFP8. fp8 KV; 262,144 tokens at 1, 2 and 4 streams,
# 131,072 for ours at 6 and 8 (production keeps 262,144); golden at one stream; repeats at 1 and 4; then one
# instrumented arm a stack (kernel log, decode window closed by a trailing request). Cells in bench/sn/; SN-DONE.
set -u
cd ~/work/target || exit 1
OUT=bench/sn
mkdir -p "$OUT"
eval "$(grep '^PE=' rfarm2.sh)"
NV_ID=nvidia/Qwen3.8-Flash-Next-FP4-Local
NV_REV=b9ce18a6887e18c089fdea8509a33e63429a3300
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader 2>/dev/null | tr -d ' '; }
close_window() {
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
}
finish() { # name streams out [instrumented]
  local n=$1 c=$2 out=$3
  echo "=== $n C=$c gpu $(gpu) $(date -Is) $(grep -a -m1 -E 'answered|ERROR|rror:' "$out/boot.log" | cut -c1-160)"
  if [ "$c" = 1 ] && [ -z "${4:-}" ]; then ( cd ~/work && timeout 900 python3 qf_harness.py golden "$HOME/work/target/$out/zgold.json" 2>&1 | tail -1 ); fi
  timeout 1800 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "sn-$n-c$c" "$c" "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  [ -n "${4:-}" ] && close_window
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  grep -a -m2 -E "self-check|sequence memory|a stream at" "$out/logs.txt" | cut -c1-170
  [ -n "${4:-}" ] && echo "kernel windows $(grep -ac '^kernel log: window' "$out/logs.txt")"
}
ours() { # name image streams context instrumented(0/1) extra-env...
  local n=$1 img=$2 c=$3 ctx=$4 ins=$5; shift 5
  local out="$OUT/$n-c$c"; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL="$c" CONTEXT="$ctx" HOST=127.0.0.1 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  if [ "$ins" = 1 ]; then finish "$n" "$c" "$out" ins; else finish "$n" "$c" "$out"; fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
prod() { # name image streams instrumented(0/1) extra-env...
  local n=$1 img=$2 c=$3 ins=$4; shift 4
  local out="$OUT/$n-c$c"; mkdir -p "$out"
  ( cd "$HOME/qwen-zig-prod" && env $PE "$@" MODEL_ID=$NV_ID MODEL_REVISION=$NV_REV IMAGE="tensorfold-qwen38:$img" VISION=0 \
      PREPARE=0 PARALLEL="$c" WAIT_TIMEOUT=3600 HOST=127.0.0.1 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  if [ "$ins" = 1 ]; then finish "$n" "$c" "$out" ins; else finish "$n" "$c" "$out"; fi
  docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1; sleep 5
}
while pgrep -f "bash \./[a-z0-9_]+\.sh" > /dev/null; do sleep 20; done
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
(
  flock -w 7200 9 || exit 1
  echo "lock $(date -Is)"
  P=zmerge8-kfix-e5139fcd8c6101c7
  for c in 1 2 4 6 8; do prod prod "$P" "$c" 0; done
  ours v16b v16 1 262144 0; prod prodr "$P" 1 0; ours v16b v16 4 262144 0; prod prodr "$P" 4 0
  prod pdiagx pdiagx 1 1 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_GRAPH_FAIL=1
) > sn2.log 2>&1 9> ~/work/gpu.lock
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> sn2.log
curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-80 >> sn2.log
touch SN2-DONE
