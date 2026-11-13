#!/usr/bin/env bash
# sameckpt.sh - our engine on production's checkpoint. Production (its own launcher and env), our 14-patch series
# (v16, drafter MXFP8 on) and stock v1.2.7 (up127) on azampatti's INT4-AutoRound, fp8 KV, 262,144 tokens at 1, 2 and
# 4 streams and 131,072 at 6 and 8 for ours (production keeps its own 262,144), one fresh boot a cell, golden at one
# stream, one decode pass of prose and code; repeats at 1 and 4; then one instrumented arm of ours (kernel log, decode
# window closed by a trailing request). Cells in bench/sc/. Production restored at the end, SC-DONE marks it.
set -u
cd ~/work/target || exit 1
OUT=bench/sc
mkdir -p "$OUT"
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader 2>/dev/null | tr -d ' '; }
finish() { # name streams out
  local n=$1 c=$2 out=$3
  echo "=== $n C=$c gpu $(gpu) $(date -Is) $(grep -a -m1 -E 'answered|ERROR|rror:' "$out/boot.log" | cut -c1-160)"
  if [ "$c" = 1 ]; then ( cd ~/work && timeout 900 python3 qf_harness.py golden "$HOME/work/target/$out/zgold.json" 2>&1 | tail -1 ); fi
  timeout 1800 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "sc-$n-c$c" "$c" "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  grep -a -m3 -E "self-check|a stream at|at once|routes|top-k" "$out/logs.txt" | cut -c1-170
}
ours() { # name image streams context extra-env...
  local n=$1 img=$2 c=$3 ctx=$4; shift 4
  local out="$OUT/$n-c$c"; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=int4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL="$c" CONTEXT="$ctx" HOST=127.0.0.1 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  finish "$n" "$c" "$out"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
prod() { # name streams
  local n=$1 c=$2 out="$OUT/$1-c$2"; mkdir -p "$out"
  ( env LOCK_HOLDER=0 PARALLEL="$c" HOST=127.0.0.1 ~/qwen6-start-prod.sh </dev/null ) > "$out/boot.log" 2>&1
  finish "$n" "$c" "$out"
  docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1; sleep 5
}
instr() { # our instrumented arm on the same checkpoint, one stream
  local out="$OUT/v16x-c1"; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 IMAGE=tensorfold-qwen38:v16x CHECKPOINT=int4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=1 CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 \
      TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  echo "=== v16x-instrumented C=1 $(date -Is) $(grep -a -m1 -E 'answered|ERROR|rror:' "$out/boot.log" | cut -c1-160)"
  timeout 1800 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" sc-v16x-c1 1 "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  echo "kernel windows $(grep -ac '^kernel log: window' "$out/logs.txt")"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
while pgrep -f "bash \./[a-z0-9_]+\.sh" > /dev/null; do sleep 20; done
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
docker stop -t 60 qwen38-flash-next-tf > /dev/null 2>&1; docker rm -f qwen38-flash-next-tf > /dev/null 2>&1
(
  flock -w 7200 9 || exit 1
  echo "lock $(date -Is)"
  M=TF_FLASHNEXT_MTP_MXFP8=1
  for c in 1 2 4; do prod prod "$c"; ours v16 v16 "$c" 262144 "$M"; ours up127 up127 "$c" 262144; done
  for c in 6 8; do prod prod "$c"; ours v16 v16 "$c" 131072 "$M"; ours up127 up127 "$c" 131072; done
  ours v16r v16 1 262144 "$M"; prod prodr 1; ours v16r v16 4 262144 "$M"; prod prodr 4
  instr
) > sc.log 2>&1 9> ~/work/gpu.lock
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> sc.log
curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-80 >> sc.log
touch SC-DONE
