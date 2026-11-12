#!/usr/bin/env bash
# wtchain.sh - the 0014 lever end to end on spark6, nothing compiled beside a timed arm: wait for the v14 image,
# build v14k (the same tree with the round and kernel logs), run widetile.sh's A/B arms, then the two profiles
# (round log and kernel table, the switch off and on). Production is restored by widetile.sh and again at the end.
set -u
cd ~/work/target || exit 1
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
for i in $(seq 1 180); do docker image inspect tensorfold-qwen38:v14 > /dev/null 2>&1 && break; sleep 20; done
docker image inspect tensorfold-qwen38:v14 > /dev/null 2>&1 || { echo "wtchain: no v14 image, stopping"; touch WTCHAIN-DONE; exit 1; }
echo "=== v14k build $(date -Is)"
BASE=$BASE127 bash ./build_rung.sh v14k rungs127/v14k.patch
docker image inspect tensorfold-qwen38:v14k > /dev/null 2>&1 || { echo "wtchain: no v14k image, stopping"; touch WTCHAIN-DONE; exit 1; }
echo "=== arms $(date -Is)"
bash ./widetile.sh > widetile.out 2>&1
echo "=== profiles $(date -Is)"
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
(
  flock -w 1800 9 || { echo "wtchain: the GPU lock is held"; exit 1; }
  bash ./profile_round.sh v14k rungs127/v14k.patch "off:" "on:TF_FLASHNEXT_DECODE_WIDE=1" \
    "koff:TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1" \
    "kon:TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_DECODE_WIDE=1"
) > wtprof.log 2>&1 9> ~/work/gpu.lock
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== done $(date -Is)"
touch WTCHAIN-DONE
