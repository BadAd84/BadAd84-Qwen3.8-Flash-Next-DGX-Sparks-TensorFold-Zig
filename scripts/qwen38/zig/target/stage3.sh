#!/usr/bin/env bash
# stage3.sh - step three of the owner's procedure: our levers added ONE RUNG AT A TIME on stock, each measured
# against the rung before it. bf16 KV at 131,072 tokens (what the pristine engine can serve at four streams), the
# upstream recipe's own environment (stage 2 found nothing better), a fresh boot a cell at C=1 and C=4.
# Per rung: decode, golden against stock's golden, and the boot self-check line. Production restored at the end.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f RUNGS2-DONE ] && break; sleep 30; done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > stage3.log
run() { # name image [env...]
  local name=$1 img=$2; shift 2
  if ! docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1; then echo "=== $name: image $img missing (did not build)" >> stage3.log; return; fi
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:$*" >> stage3.log 2>&1
}
run s3warm up126
run s3stock up126
run s3r05rows stack126a
run s3r12kv8 rung2
run s3r15ngram rung3
run s3r17chunk r0017
run s3r19gemm2 r0019
run s3r21head r0021
run s3r25hc r0025
run s3r26q12 r0026
run s3r27cost r0027
run s3r29vision r0029
run s3r32all r0032
run s3stock2 up126
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== stage 3 done, production restored $(date -Is)" >> stage3.log
touch STAGE3-DONE
