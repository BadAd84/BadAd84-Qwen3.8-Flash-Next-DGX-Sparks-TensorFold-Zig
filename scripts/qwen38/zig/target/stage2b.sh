#!/usr/bin/env bash
# stage2b.sh - the rest of step two (env tuning on STOCK, no patches): the upstream knobs the first pass left out,
# led by TF_FLASHNEXT_DRAFT_HEAD=affine4, which our "draft head" patch merely makes the default. One knob an arm on
# the pristine image, then the winners stacked, bracketed by baselines. bf16, 131,072 tokens.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f STAGE3B-DONE ] && break; sleep 30; done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
IMG=tensorfold-qwen38:up126 bash ./patcheval.sh \
  "t2warm:" "t2base:" \
  "t2head4:TF_FLASHNEXT_DRAFT_HEAD=affine4" \
  "t2greedy12:TF_FLASHNEXT_DRAFTS_GREEDY=12" \
  "t2greedy16:TF_FLASHNEXT_DRAFTS_GREEDY=16" \
  "t2tablewarm:TF_FLASHNEXT_TABLE_WARM=1" \
  "t2batchheads0:TF_FLASHNEXT_BATCH_HEADS=0" \
  "t2shareddrafts0:TF_FLASHNEXT_SHARED_DRAFTS=0" \
  "t2keepinpass0:TF_FLASHNEXT_KEEP_INPASS=0" \
  "t2laneparts0:TF_FLASHNEXT_LANE_PARTS=0" \
  "t2promptbf160:TF_FLASHNEXT_PROMPT_BF16=0" \
  "t2gputopk0:TF_FLASHNEXT_GPU_TOPK=0" \
  "t2readout128:TF_FLASHNEXT_READOUT_ROWS=128" \
  "t2fact128:TF_FLASHNEXT_FACT_ROWS=128" \
  "t2base2:" \
  "t2head4b:TF_FLASHNEXT_DRAFT_HEAD=affine4" \
  "t2head4greedy12:TF_FLASHNEXT_DRAFT_HEAD=affine4 TF_FLASHNEXT_DRAFTS_GREEDY=12" \
  "t2base3:" > stage2b.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch STAGE2B-DONE
