#!/usr/bin/env bash
# mverify5.sh (under the GPU lock): the stop-rule shootout on zmerge3. Warm-up discarded, then base, fable, opus, glm,
# glm, opus, fable, base (each candidate twice, mirrored order). Each boot: golden + decode matrix.
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1"
BASE="$COMMON IMAGE=tensorfold-qwen38:zmerge3"
FABLE="$COMMON IMAGE=tensorfold-qwen38:zstop-fable TF_FLASHNEXT_PROPOSE=0.05 TF_FLASHNEXT_PROPOSE_TPR=4"
OPUS="$COMMON IMAGE=tensorfold-qwen38:zstop-opus TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7"
CAL=$(grep TUNE_CAL ~/work/lanes/prose-glm/tune.env | cut -d= -f2)
GLM="$COMMON IMAGE=tensorfold-qwen38:zstop-glm TF_FLASHNEXT_CHAIN_RULE=cum TF_FLASHNEXT_CHAIN_T=0.25 TF_FLASHNEXT_CAL=$CAL"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "propose floor\|chain rule\|CHAIN\|W6\|draft head" | head -3
}
arm v5warm $BASE
arm v5base1 $BASE
arm v5fable1 $FABLE
arm v5opus1 $OPUS
arm v5glm1 $GLM
arm v5glm2 $GLM
arm v5opus2 $OPUS
arm v5fable2 $FABLE
arm v5base2 $BASE
echo "##### done $(date -Is)"
