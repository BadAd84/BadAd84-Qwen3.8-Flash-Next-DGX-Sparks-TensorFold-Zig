#!/usr/bin/env bash
# widetile.sh - patch 0014 (TF_FLASHNEXT_DECODE_WIDE) on one binary: image v14 = v1.2.7 + the 13 levers + 0014,
# the switch off and on at 1, 2, 4, 6 and 8 streams (bf16 KV, 131,072 tokens, HOST=127.0.0.1 so nothing outside
# reaches the arm), one fresh boot a cell, golden against v1.2.6 stock's, a discarded warm-up arm first and the
# baseline repeated. Holds the box's GPU lock for the arms and restores the production serve at the end.
set -u
cd ~/work/target || exit 1
IMGTAG=${IMGTAG:-v14}
KNOB=${KNOB:-TF_FLASHNEXT_DECODE_WIDE=1}
LOG=${LOG:-widetile.log}
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > "$LOG"

run() { # name env-string
  local name=$1 envs=$2
  IMG="tensorfold-qwen38:$IMGTAG" bash ./patcheval.sh "$name:$envs" >> "$LOG" 2>&1
  for C in $STREAMS; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1)" >> "$LOG"
  done
}

# the production serve holds the lock while it runs, so it stops before the lock is taken
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
(
  flock -w 1800 9 || { echo "widetile: the GPU lock is held"; exit 1; }
  echo "=== 1 and 4 stream cells $(date -Is)" | tee -a "$LOG"
  export STREAMS="1 4"
  run wtwarm ""
  run wtoff ""
  run wton "$KNOB"
  run wtoff2 ""
  run wton2 "$KNOB"
  echo "=== 2, 6 and 8 stream cells $(date -Is)" | tee -a "$LOG"
  export STREAMS="2 6 8"
  run wtoff8 ""
  run wton8 "$KNOB"
) 9> ~/work/gpu.lock
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== production $(date -Is)"
touch "$HOME/work/target/WIDETILE-DONE"
