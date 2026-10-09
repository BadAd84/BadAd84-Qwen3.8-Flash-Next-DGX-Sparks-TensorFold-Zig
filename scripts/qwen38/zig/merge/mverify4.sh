#!/usr/bin/env bash
# mverify4.sh (under the GPU lock): zmerge3 (zmerge2 + W8 fused FP8 split-K + lm_head MT2 + W5 up-mix at decode)
# against zmerge2. Warm-up discarded, then m2, m3, m3, m2. Each: golden + decode matrix + copy/rewrite.
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1"
M2="$COMMON IMAGE=tensorfold-qwen38:zmerge2"
M3="$COMMON IMAGE=tensorfold-qwen38:zmerge3 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "ots w8\|W8\|up_mix\|UPMIX" | head -3
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 2
}
WARM=1 arm v4warm $M2
arm v4m2a $M2
arm v4m3a $M3
arm v4m3b $M3
arm v4m2b $M2
echo "##### done $(date -Is)"
