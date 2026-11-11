#!/usr/bin/env bash
# final_check.sh - after the post-sweep steps: rebuild stack126 from the final series (relaxed tile off by default,
# so the boot self-check should find the 48-row boundary again), boot it, read the self-check and one request,
# then restore the production serve and touch FINAL-DONE.
set -u
cd "$HOME/work/target" || exit 1
while [ ! -f POST-DONE ]; do sleep 60; done
echo "=== final rebuild from $(ls patches126/*.patch | wc -l) patches $(date -Is)"
bash "$HOME/work/target/build_patches.sh" stack126 git://192.168.99.16/up-pr/tf \
  6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$HOME/work/target/patches126" > build-final.log 2>&1
echo "build rc=$? $(grep -aE '^BUILT|error:' build-final.log | head -2)"
bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:stack126 embedded > /dev/null 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE=tensorfold-qwen38:stack126 CHECKPOINT=nvfp4 VISION=0 \
    TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=3 CONTEXT=131072 HOST=127.0.0.1 ./start.sh restart </dev/null ) \
  > final-boot.log 2>&1
echo "boot rc=$? $(grep -aE 'Server answered|LIVE|ERROR' final-boot.log | tail -1)"
docker logs qwen38-flash-next-tf 2>&1 | grep -aE "self-check|copy windows|prompt=" | tail -3
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -4
echo "=== production restored $(date -Is)"
touch "$HOME/work/target/FINAL-DONE"
