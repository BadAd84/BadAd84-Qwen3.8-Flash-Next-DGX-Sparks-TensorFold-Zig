#!/usr/bin/env bash
# fp8pages.sh [TAG] [PREFIX] - patch 0015 (fp8 rows on every served stream and in the shared page pool) end to end on
# spark6: build image TAG (the 14 levers + 0015, rungs127/TAG.patch), measure the fp8 kernels' nvcc resources
# (fp8res.sh), then fresh-boot cells at fp8 KV and a 262,144 window: unpaged fp8 at 1/2/4, every stream on pages at
# 1/2/4, the pool beside the own stream at 1/6/8, and repeats of the 1-stream cells. Golden against stock, paged against
# unpaged (golden and every decode reply's sha). Takes the GPU lock first; production is restored inside it.
set -u
cd ~/work/target || exit 1
TAG=${1:-fp8pg}; P=${2:-f8}
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
LOG=fp8pages-$TAG.log
SUM=fp8pages-$TAG.sum
: > "$LOG"
(
  flock -w 14400 9 || { echo "fp8pages: the GPU lock is held" >> "$LOG"; exit 1; }
  echo "=== lock $(date -Is)" >> "$LOG"
  BASE=$BASE127 bash ./build_rung.sh "$TAG" "rungs127/$TAG.patch" >> "$LOG" 2>&1
  docker image inspect "tensorfold-qwen38:$TAG" > /dev/null 2>&1 || { echo "fp8pages: no $TAG image" >> "$LOG"; exit 1; }
  echo "=== resources $(date -Is)" >> "$LOG"
  bash ./fp8res.sh "$TAG" > "fp8res-$TAG.txt" 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  export NORESTORE=1 KV_DTYPE=fp8 CONTEXT=262144 HOLD_FILE=none
  arm() { # streams name:env
    echo "=== arm $2 C=[$1] $(date -Is)" >> "$LOG"
    IMG="tensorfold-qwen38:$TAG" STREAMS="$1" bash ./patcheval.sh "$2" >> "$LOG" 2>&1
  }
  arm "1 2 4" "${P}u:"
  arm "1 2 4" "${P}pa:TF_FLASHNEXT_KV_PAGES=4096 TF_FLASHNEXT_KV_PAGES_ALL=1"
  arm "1 6 8" "${P}p:TF_FLASHNEXT_KV_PAGES=4096"
  arm 1 "${P}u2:"
  arm 1 "${P}p2:TF_FLASHNEXT_KV_PAGES=4096"
  arm 1 "${P}pa2:TF_FLASHNEXT_KV_PAGES=4096 TF_FLASHNEXT_KV_PAGES_ALL=1"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> "$LOG"
  echo "=== restored $(date -Is)" >> "$LOG"
) 9> ~/work/gpu.lock
{
  for d in bench/pe-"$P"*/c*; do
    [ -f "$d/zgold.json" ] || { echo "$d: no golden"; continue; }
    echo "GOLD $d $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "$d/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]*/[0-9]* identical')"
    grep -a "self-check: \|KV page groups\|streams at once\|stream at once\|error" "$d/logs.txt" 2>/dev/null | cut -c1-330 | head -4
  done
  for c in 1 2 4; do
    echo "PAGED-vs-UNPAGED c$c golden: $(python3 ~/work/zgold_cmp.py "bench/pe-${P}u/c$c/zgold.json" "bench/pe-${P}pa/c$c/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]*/[0-9]* identical')"
    echo "PAGED-vs-UNPAGED c$c decode: $(python3 fp8cmp.py "bench/pe-${P}u/c$c/dec.jsonl" "bench/pe-${P}pa/c$c/dec.jsonl" 2>&1 | tail -1)"
  done
  for b in p u2 p2 pa2; do
    echo "DECODE ${P}u against ${P}$b c1: $(python3 fp8cmp.py "bench/pe-${P}u/c1/dec.jsonl" "bench/pe-${P}$b/c1/dec.jsonl" 2>&1 | tail -1)"
  done
  grep -a "^=== \|^DEC\|^build" "$LOG"
} > "$SUM" 2>&1
touch "FP8PAGES-$TAG-DONE"
