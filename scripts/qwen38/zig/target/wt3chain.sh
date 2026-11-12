#!/usr/bin/env bash
# wt3chain.sh - behind the q12 chain: image v15 (the 13 levers + 0014 with the instance switch) and the two
# instances of the 128-column tile measured against the switch off on that one binary, at 1 and 4 streams.
# TF_FLASHNEXT_DECODE_WIDE_K32=0 is the three-stage K64 instance (one bulk copy a stage), 1 the K32 one.
set -u
cd ~/work/target || exit 1
BASE127=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
for i in $(seq 1 480); do [ -f WT2CHAIN-DONE ] && break; sleep 30; done
[ -f WT2CHAIN-DONE ] || { echo "wt3chain: the q12 chain never finished"; exit 1; }
echo "=== v15 build $(date -Is)"
BASE=$BASE127 bash ./build_rung.sh v15 rungs127/v15.patch
docker image inspect tensorfold-qwen38:v15 > /dev/null 2>&1 || { echo "wt3chain: no v15 image, stopping"; touch WT3CHAIN-DONE; exit 1; }
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1 STREAMS="1 4"
LOG=widetile3.log
: > "$LOG"
run() { # name env-string
  local name=$1 envs=$2
  IMG="tensorfold-qwen38:v15" bash ./patcheval.sh "$name:$envs" >> "$LOG" 2>&1
  for C in $STREAMS; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1)" >> "$LOG"
  done
}
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
(
  flock -w 1800 9 || { echo "wt3chain: the GPU lock is held"; exit 1; }
  echo "=== arms $(date -Is)"
  run w3warm ""
  run w3off ""
  run w3k64 "TF_FLASHNEXT_DECODE_WIDE=1 TF_FLASHNEXT_DECODE_WIDE_K32=0"
  run w3k32 "TF_FLASHNEXT_DECODE_WIDE=1"
  run w3off2 ""
  run w3k64b "TF_FLASHNEXT_DECODE_WIDE=1 TF_FLASHNEXT_DECODE_WIDE_K32=0"
) 9> ~/work/gpu.lock
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== done $(date -Is)"
touch "$HOME/work/target/WT3CHAIN-DONE"
