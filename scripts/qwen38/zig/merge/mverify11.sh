#!/usr/bin/env bash
# mverify11.sh (under the GPU lock): the clean upstream stack zpr-stack (0010-0020, renamed settings, experiments
# stripped) against zmerge5. Warm-up discarded, then m5, pr, pr, m5. Each: golden + decode matrix + copy/rewrite +
# concurrent edits + cold prefill + the boot lines that prove each setting engaged.
set -uo pipefail
cd ~/work/merge/v || exit 1
BASE="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15"
M5="$BASE IMAGE=tensorfold-qwen38:zmerge5 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_COPY_SHARED=1"
PR="$BASE IMAGE=tensorfold-qwen38:zpr-stack TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_COPY_RESYNC=1 TF_FLASHNEXT_COPY_RAMP=jump TF_FLASHNEXT_COPY_MISS=keep TF_FLASHNEXT_COPY_SHARED=1 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_BATCH_DRAWS=1 TF_FLASHNEXT_BATCH_WINDOWS=1 TF_FLASHNEXT_FP8_FUSED_SPLIT=4 TF_FLASHNEXT_HEAD_ROW_TILES=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_REDUCE_ACT=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_DRAFT_PROPOSE=0.05 TF_FLASHNEXT_DRAFT_CONTINUE=0.20 TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -av "│" | grep -a "^info\|copy policy\|w6\|ots\|draft\|pool\|n-gram\|window\|fused\|row tiles" | grep -v "costs:" | head -14
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 2
  python3 w2copy.py "$l" "w2-$l.jsonl" 2 edit2,editprose 2>&1 | grep "median"
  python3 pf2.py "$l" "zp-$l.jsonl" "$(( 900000 + RANDOM * 64 ))" | grep median
}
WARM=1 arm v11warm $M5
arm v11m5a $M5
arm v11pra $PR
arm v11prb $PR
arm v11m5b $M5
echo "##### done $(date -Is)"
