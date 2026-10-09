#!/usr/bin/env bash
# mverify3.sh (under the GPU lock): zmerge2 (zmerge1 + W3 pool/warm) against zmerge1 and stock. Warm-up boot
# discarded, then base, m1, m2, m2, m1, base. Each: golden + decode matrix (zarm.sh) + short replies (w3bench short if
# present, else 100-token qf prompts) + cold prefill 8k/32k with fresh text + free memory after boot.
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15"
BASE="$COMMON IMAGE=tensorfold-qwen38:zots5"
M1="$COMMON IMAGE=tensorfold-qwen38:zmerge1 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64"
M2="${M1/zmerge1/zmerge2} TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  free -g | awk '/Mem/{print "free GiB:", $4, "available:", $7}'
  [[ "${WARM:-0}" == 1 ]] && return
  python3 short.py "$l" "zs-$l.jsonl"
  python3 pf2.py "$l" "zp-$l.jsonl" "$(( 400000 + RANDOM * 64 ))" | grep median
}
WARM=1 arm v3warm $BASE
arm v3b1 $BASE
arm v3m1a $M1
arm v3m2a $M2
arm v3m2b $M2
arm v3m1b $M1
arm v3b2 $BASE
echo "##### done $(date -Is)"
