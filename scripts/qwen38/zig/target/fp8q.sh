#!/usr/bin/env bash
# fp8q.sh - the pool beside the engine's own stream (TF_FLASHNEXT_KV_PAGES=4096) at 2 and 4 streams on image fp8pg2, fp8
# KV, a 262,144 window: golden against stock and every decode reply against the unpaged cells of fp8pages.sh (g8u).
set -u
cd ~/work/target || exit 1
(
  flock -w 7200 9 || { echo "fp8q: the GPU lock is held" > fp8q.log; exit 1; }
  echo "=== lock $(date -Is)" > fp8q.log
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  NORESTORE=1 KV_DTYPE=fp8 CONTEXT=262144 HOLD_FILE=none IMG=tensorfold-qwen38:fp8pg2 STREAMS="2 4" \
    bash ./patcheval.sh "g8q:TF_FLASHNEXT_KV_PAGES=4096" >> fp8q.log 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> fp8q.log
  echo "=== restored $(date -Is)" >> fp8q.log
) 9> ~/work/gpu.lock
for c in 2 4; do
  echo "GOLD c$c $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json bench/pe-g8q/c$c/zgold.json 2>&1 | tail -1 | grep -o '[0-9]*/[0-9]* identical'); decode $(python3 fp8cmp.py bench/pe-g8u/c$c/dec.jsonl bench/pe-g8q/c$c/dec.jsonl 2>&1 | tail -1)" >> fp8q.log
done
touch FP8Q-DONE
