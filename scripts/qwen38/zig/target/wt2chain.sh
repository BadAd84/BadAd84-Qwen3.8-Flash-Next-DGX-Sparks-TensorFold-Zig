#!/usr/bin/env bash
# wt2chain.sh - behind the 0014 chain, on the same binary (image v14): the lossless 12-bit read-out copy
# (TF_FLASHNEXT_HC_Q12=1, patch 0009's lever, which the production launcher sets) alone and with the wide tile, the
# baseline once more for drift, then the cold 8k and 32k prompts with the switch off, on, and on the q12 copy.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 480); do [ -f WTCHAIN-DONE ] && break; sleep 30; done
[ -f WTCHAIN-DONE ] || { echo "wt2chain: the first chain never finished"; exit 1; }
IMGTAG=${IMGTAG:-v14}
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1 STREAMS="1 4"
LOG=widetile2.log
: > "$LOG"
run() { # name env-string
  local name=$1 envs=$2
  IMG="tensorfold-qwen38:$IMGTAG" bash ./patcheval.sh "$name:$envs" >> "$LOG" 2>&1
  for C in $STREAMS; do
    echo "GOLD $name c$C $(python3 ~/work/zgold_cmp.py bench/pe-s3stock/c1/zgold.json "bench/pe-$name/c$C/zgold.json" 2>&1 | tail -1)" >> "$LOG"
  done
}
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
(
  flock -w 1800 9 || { echo "wt2chain: the GPU lock is held"; exit 1; }
  echo "=== q12 arms $(date -Is)"
  run wtoff3 ""
  run wtq12 "TF_FLASHNEXT_HC_Q12=1"
  run wtq12wide "TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_DECODE_WIDE=1"
  echo "=== cold prompts $(date -Is)"
  bash ./prefill_arm.sh "wtpfoff:$IMGTAG:" "wtpfon:$IMGTAG:TF_FLASHNEXT_DECODE_WIDE=1" "wtpfq12:$IMGTAG:TF_FLASHNEXT_HC_Q12=1" "wtpfoff2:$IMGTAG:"
) 9> ~/work/gpu.lock
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== done $(date -Is)"
touch "$HOME/work/target/WT2CHAIN-DONE"
