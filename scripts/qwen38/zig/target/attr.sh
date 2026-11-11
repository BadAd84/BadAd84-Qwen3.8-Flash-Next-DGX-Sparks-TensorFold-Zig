#!/usr/bin/env bash
# attr.sh - attribute production's decode lead by switching its own levers off, one arm each, on the production
# tree (where every knob exists). Baseline: the production image with the production launcher's environment, one
# fresh container a setting. Decode only: one pass, one stream, code prompt; plus the boot self-check line.
set -u
cd ~/work/target || exit 1
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
docker tag tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 tensorfold-qwen38:prodbench >/dev/null 2>&1
bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:prodbench embedded >/dev/null 2>&1
run() {
  local name=$1 extra=$2
  docker rm -f qwen38-flash-next-tf >/dev/null 2>&1
  echo "=== $name extra: $extra $(date -Is)"
  ( cd ~/work/lanes/rpr/recipe && env $E $extra PREPARE=0 IMAGE=tensorfold-qwen38:prodbench CHECKPOINT=nvfp4 \
      VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=1 CONTEXT=262144 HOST=127.0.0.1 \
      ./start.sh restart </dev/null ) > "/tmp/attr-$name.log" 2>&1
  docker inspect -f 'container created {{.Created}}' qwen38-flash-next-tf 2>/dev/null
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "self-check\|copy windows\|drafts:" | head -2 | cut -c1-120
  python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "attr-$name" 1 "$HOME/work/target/bench/attr-$name/dec.jsonl" 1 \
    | grep -a "^DEC" | head -3 | cut -c1-110
}
mkdir -p bench/attr-base bench/attr-nomtpq4 bench/attr-nodraftint4 bench/attr-noup mix bench/attr-noqsa bench/attr-noearly
run base ""
run nomtpq4 "TF_FLASHNEXT_MTP_Q4=0"
run nodraftint4 "TF_FLASHNEXT_DRAFT_INT4=0"
for pair in "noup:TF_FLASHNEXT_UPMIX_DECODE=0" "noqsa:TF_FLASHNEXT_QSA_SELECT=0" "noearly:TF_FLASHNEXT_EARLY_DRAW=0"; do
  run "${pair%%:*}" "${pair##*:}"
done
docker rm -f qwen38-flash-next-tf >/dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== production $(date -Is)"
touch "$HOME/work/target/ATTR-DONE"
