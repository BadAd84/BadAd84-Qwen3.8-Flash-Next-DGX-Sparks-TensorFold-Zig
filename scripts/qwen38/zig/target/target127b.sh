#!/usr/bin/env bash
# target127b.sh - what target127.sh could not serve: at fp8 KV and a 262,144 window 6 and 8 streams need 30.2 and 40.3
# GiB of stream memory against a 27.3 GiB budget (production fits them with TF_FLASHNEXT_SEQ_POOL=8, which this series
# does not carry). So: image v7 at 6 and 8 streams on a 131,072 window (fp8 KV), and the v13 one-stream cell that
# target127.sh lost to a missing container. Same lock, restore at the end.
set -u
cd ~/work/target || exit 1
exec 9>~/work/gpu.lock
flock -w 7200 9 || { echo "target127b: the GPU lock is held"; exit 1; }
: > target127b.log
export NORESTORE=1 KV_DTYPE=fp8
CONTEXT=131072 STREAMS="6 8" IMG=tensorfold-qwen38:v7 HOLD_FILE=none bash ./patcheval.sh "t127w131:" >> target127b.log 2>&1
CONTEXT=262144 STREAMS="1" IMG=tensorfold-qwen38:v13 HOLD_FILE=none bash ./patcheval.sh "t127v13r:" >> target127b.log 2>&1
CONTEXT=262144 STREAMS="5" IMG=tensorfold-qwen38:v7 HOLD_FILE=none bash ./patcheval.sh "t127five:" >> target127b.log 2>&1
for n in t127w131:6 t127w131:8 t127v13r:1 t127five:5; do
  echo "GOLD ${n%%:*} c${n##*:} $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-${n%%:*}/c${n##*:}/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]/6 [a-z]*')" >> target127b.log
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> target127b.log
touch TARGET127B-DONE
