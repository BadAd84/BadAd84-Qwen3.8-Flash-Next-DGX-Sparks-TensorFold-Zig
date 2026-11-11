#!/usr/bin/env bash
# envprod.sh - our 1.2.6 stack with production's tuned TF_FLASHNEXT environment (the 1.0.0 values in
# ~/qwen6-start-prod.sh), at the target settings: nvfp4, fp8 KV, 262,144 tokens. Cells at 1 and 4 streams, then
# the production serve restored. Knobs 1.2.6 does not know are reported by the engine and ignored.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 480); do [ -f NOQ12-DONE ] && break; sleep 30; done
echo "=== no-q12 done, running the production env on our stack $(date -Is)"
E="TF_FLASHNEXT_BATCH_DRAWS=1 TF_FLASHNEXT_BATCH_WINDOWS=1 TF_FLASHNEXT_CONFIDENCE=-0.15"
E="$E TF_FLASHNEXT_COPY_MISS=keep TF_FLASHNEXT_COPY_RAMP=jump TF_FLASHNEXT_COPY_RESYNC=1 TF_FLASHNEXT_COPY_SHARED=1"
E="$E TF_FLASHNEXT_COST_RETIME=4 TF_FLASHNEXT_DEPTH=15 TF_FLASHNEXT_DRAFT_CONTINUE=0.20"
E="$E TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_DRAFT_PROPOSE=0.05"
E="$E TF_FLASHNEXT_EARLY_DRAW=1 TF_FLASHNEXT_FP8_FUSED_SPLIT=4 TF_FLASHNEXT_FP8_PROMPT_TILES=1 TF_FLASHNEXT_HC_Q12=1"
E="$E TF_FLASHNEXT_HEAD_ROW_TILES=2 TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1 TF_FLASHNEXT_MULTI_LRU=1"
E="$E TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_NGRAM_LATE=1 TF_FLASHNEXT_NGRAM_PREFETCH=1"
E="$E TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_PREFILL_ROWS=4096"
E="$E TF_FLASHNEXT_PREFILL_TAIL=512 TF_FLASHNEXT_PRODUCT_STREAMS=8 TF_FLASHNEXT_PROMPT_HEAD_SKIP=1"
E="$E TF_FLASHNEXT_QSA_SELECT=1 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_REDUCE_ACT=1 TF_FLASHNEXT_SEQ_POOL=8"
E="$E TF_FLASHNEXT_SHARED_EARLY_ROWS=6 TF_FLASHNEXT_SHARED_SLOT_LD=1 TF_FLASHNEXT_SOLO_MAX=1024"
E="$E TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_WARM_POOL=8 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_YARN=0"
E="$E TF_FLASHNEXT_SHARED_COST_LEVELS=0"
for C in 1 4; do
  IMG=tensorfold-qwen38:stack126 CHKPT=nvfp4 KV_DTYPE=fp8 CONTEXT=262144 ARM_ENV="$E" \
    bash ./bench_arm.sh "envprod" "$C"
  echo "cell envprod C=$C $(grep -aE '^BOOT seconds|^GOLD exit|^BOOT FAILED' "bench/envprod/c$C/arm.log" | tr '\n' ' ')"
  grep -a "serving 32-row\|serving 48-row\|are row-equal" "bench/envprod/c$C/boot.log" | cut -c1-120
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|rror" | head -2
echo "=== production $(date -Is)"
touch "$HOME/work/target/ENVPROD-DONE"
