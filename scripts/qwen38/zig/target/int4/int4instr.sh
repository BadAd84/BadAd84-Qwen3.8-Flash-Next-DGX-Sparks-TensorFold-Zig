#!/usr/bin/env bash
# int4instr.sh - our INT4-AutoRound engine with the kernel and expert logs (image int4x = 0016 + the diag patch), one
# stream, graphs off, one decode pass of prose and code, the decode window closed by a trailing request; production
# restored after. Output: ~/work/int4/bench-int4x/ep-o1/. The GPU lock is held for the run.
set -u
OUT=$HOME/work/int4/bench-int4x/ep-o1
mkdir -p "$OUT"
bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:int4x embedded > /dev/null 2>&1
(
  flock 9
  echo "=== lock $(date -Is)"
  trap '( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1; ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/restore.log" 2>&1; echo "=== restored $(date -Is) health $(curl -s -o /dev/null -w "%{http_code}" -m 10 http://127.0.0.1:8888/health)"' EXIT
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 IMAGE=tensorfold-qwen38:int4x CHECKPOINT=int4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=1 CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 WAIT_TIMEOUT=3600 \
      TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_EXPERT_LOG=1 TF_FLASHNEXT_WINDOW_GRAPH=0 \
      ./start.sh restart </dev/null ) > "$OUT/boot.log" 2>&1
  echo "=== int4x C=1 $(date -Is) $(grep -a -m1 -E 'answered|ERROR|rror:' "$OUT/boot.log" | cut -c1-160)"
  timeout 2400 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" ep-int4x 1 "$OUT/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
  sleep 2
  curl -s -m 300 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
    -d '{"model":"Qwen3.8-Flash-Next","messages":[{"role":"user","content":"Say hi."}],"max_tokens":2}' > /dev/null
  sleep 3
  docker logs qwen38-flash-next-tf > "$OUT/logs.txt" 2>&1
  echo "kernel windows $(grep -ac '^kernel log: window' "$OUT/logs.txt") expert $(grep -ac '^expert log' "$OUT/logs.txt")"
) 9>"$HOME/work/gpu.lock"
touch "$OUT/DONE"
