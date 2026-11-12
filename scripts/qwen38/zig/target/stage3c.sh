#!/usr/bin/env bash
# stage3c.sh - the later levers on the repaired accepted rung (g21), each rung carrying overlay.py's repairs:
# g25 the read-out fusion group (chunk stores its position, the prompt's last row is recorded, the relaxed MX128
# tile stays off), g26 q12, g27 cost, g29 vision, g32 the reader knob and the check log.
# Decode and golden through patcheval.sh; the prompt levers are priced by cold prompt time (prefill_arm.sh), since
# a 512-token reply cannot show them. r15..r21 are the rungs before the n-gram fill repair, g21 the one after.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 1200); do [ -f "${WAIT:-NFIX-DONE}" ] && break; sleep 30; done
echo "=== building the repaired rungs $(date -Is)"
for K in 25 26 27 29 32; do bash ./build_rung.sh "g$K" "rungs/g$K.patch"; done
OFF="TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=256"
echo "=== cold prompt time $(date -Is)"
bash ./prefill_arm.sh \
  "warm:up126:" "stock:up126:" "r15:rung3:" "r17:r0017:" "r19:r0019:" "r21:r0021:" "g21:g21:" \
  "g21tail0:g21:TF_FLASHNEXT_PREFILL_TAIL=0" \
  "g21mx:g21:TF_FLASHNEXT_PROMPT_MX128=1024" \
  "g21mxg0:g21:TF_FLASHNEXT_PROMPT_MX128=1024 TF_FLASHNEXT_PROMPT_GEMM2=0" \
  "g21plain:g21:TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_DRAFT_AHEAD=0" \
  "hcoff:g25:$OFF" \
  "hc2:g25:TF_FLASHNEXT_PROMPT_HC2=1 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=256" \
  "direct:g25:TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1 TF_FLASHNEXT_HEAD_PIECE=256" \
  "piece:g25:TF_FLASHNEXT_PROMPT_HC2=0 TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0 TF_FLASHNEXT_HEAD_PIECE=1536" \
  "hcall:g25:" "q12:g26:" "cost:g27:" "all:g32:" "stock2:up126:" > stage3c.pf.log 2>&1
echo "=== decode and golden $(date -Is)"
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > stage3c.log
run() { # name image [env]
  local name=$1 img=$2; shift 2
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> stage3c.log; return; }
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:$*" >> stage3c.log 2>&1
}
run c3warm g21
run c3g21 g21
run c3hcoff g25 "$OFF"
run c3hc g25
run c3q12 g26
run c3cost g27
run c3vision g29
run c3all g32
run c3g21b g21
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch STAGE3C-DONE
