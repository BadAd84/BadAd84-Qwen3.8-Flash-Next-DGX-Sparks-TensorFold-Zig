#!/usr/bin/env bash
# mtpchain.sh - the drafter's BF16 linears re-coded to MXFP8 at load (patch 0014, TF_FLASHNEXT_MTP_WEIGHTS) end to
# end on spark6: wait for the tile chain, build v16 (the 13 levers + 0014) and v16k (the same with the round and
# kernel logs, the kernel log split by grid width), then the arms on one binary with the switch off and on at 1, 4,
# 2 and 6 streams, the cold prompts, and the two profiles. Production is restored at the end.
set -u
cd ~/work/target || exit 1
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
for i in $(seq 1 600); do [ -f WT3CHAIN-DONE ] && break; sleep 30; done
echo "=== builds $(date -Is)"
BASE=$BASE127 bash ./build_rung.sh v16 rungs127/v16.patch
BASE=$BASE127 bash ./build_rung.sh v16k rungs127/v16k.patch
docker image inspect tensorfold-qwen38:v16 > /dev/null 2>&1 || { echo "mtpchain: no v16 image"; touch MTPCHAIN-DONE; exit 1; }
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
LOG=mtp.log
: > "$LOG"
run() { # name env-string
  local name=$1 envs=$2
  IMG="tensorfold-qwen38:v16" bash ./patcheval.sh "$name:$envs" >> "$LOG" 2>&1
  for C in $STREAMS; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1)" >> "$LOG"
    grep -a "re-coded to MXFP8\|sequence memory\|Server answered" "bench/pe-$name/c$C/logs.txt" "bench/pe-$name/c$C/boot.log" 2>/dev/null | cut -c1-200 >> "$LOG"
  done
}
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
(
  flock -w 2400 9 || { echo "mtpchain: the GPU lock is held"; exit 1; }
  echo "=== 1 and 4 stream cells $(date -Is)"
  export STREAMS="1 4"
  run mtpwarm ""
  run mtpoff ""
  run mtpon "TF_FLASHNEXT_MTP_WEIGHTS=mxfp8"
  run mtpoff2 ""
  run mtpon2 "TF_FLASHNEXT_MTP_WEIGHTS=mxfp8"
  echo "=== 2 and 6 stream cells $(date -Is)"
  export STREAMS="2 6"
  run mtpoff6 ""
  run mtpon6 "TF_FLASHNEXT_MTP_WEIGHTS=mxfp8"
  echo "=== 8 streams on fp8 KV $(date -Is)"
  export STREAMS="8" KV_DTYPE=fp8
  run mtpoff8 ""
  run mtpon8 "TF_FLASHNEXT_MTP_WEIGHTS=mxfp8"
  export KV_DTYPE=bf16
  echo "=== cold prompts $(date -Is)"
  bash ./prefill_arm.sh "mtppfoff:v16:" "mtppfon:v16:TF_FLASHNEXT_MTP_WEIGHTS=mxfp8" "mtppfoff2:v16:"
  echo "=== profiles $(date -Is)"
  bash ./profile_round.sh v16k rungs127/v16k.patch "off:" "on:TF_FLASHNEXT_MTP_WEIGHTS=mxfp8" \
    "koff:TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1" \
    "kon:TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8" >> mtpprof.log 2>&1
) 9> ~/work/gpu.lock
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== done $(date -Is)"
touch "$HOME/work/target/MTPCHAIN-DONE"
