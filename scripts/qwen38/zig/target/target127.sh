#!/usr/bin/env bash
# target127.sh - the accepted stack and the whole series on v1.2.7 at the production target's own settings (fp8 KV,
# 262,144-token window) at 1, 2, 4, 6 and 8 streams: decode prose and code, golden, boot self-check. Images v7 (0001-0007,
# the accepted stack) and v13 (all 13). Holds ~/work/gpu.lock for the whole run, restores production at the end.
# Cells land in bench/pe-t127v7/, bench/pe-t127v13/. Run it detached from ~/work/target.
set -u
cd ~/work/target || exit 1
exec 9>~/work/gpu.lock
flock -w 7200 9 || { echo "target127: the GPU lock is held"; exit 1; }
export KV_DTYPE=fp8 CONTEXT=262144 NORESTORE=1 STREAMS="1 2 4 6 8"
: > target127.log
echo "=== start $(date -Is)" >> target127.log
for pair in "t127warm:v7" "t127v7:v7" "t127v13:v13" "t127v7b:v7"; do
  name=${pair%%:*}; img=${pair##*:}
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> target127.log; continue; }
  if [ "$name" = t127warm ]; then STREAMS="1" IMG="tensorfold-qwen38:$img" HOLD_FILE=none bash ./patcheval.sh "$name:" >> target127.log 2>&1; continue; fi
  IMG="tensorfold-qwen38:$img" HOLD_FILE=none bash ./patcheval.sh "$name:" >> target127.log 2>&1
  for C in $STREAMS; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1 | grep -o '[0-9]/6 [a-z]*')" >> target127.log
  done
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> target127.log
echo "=== done $(date -Is)" >> target127.log
touch TARGET127-DONE
