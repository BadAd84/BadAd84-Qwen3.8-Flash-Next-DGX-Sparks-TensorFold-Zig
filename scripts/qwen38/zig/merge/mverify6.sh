#!/usr/bin/env bash
# mverify6.sh (under the GPU lock): zmerge4 (zmerge3 + W6Opus stop rule + int4 draft head + W2 prompt-only resync)
# against zmerge3. Warm-up discarded, then m3, m4, m4, m3. Each: golden + decode matrix + copy/rewrite + cold prefill.
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1"
M3="$COMMON IMAGE=tensorfold-qwen38:zmerge3"
M4="$COMMON IMAGE=tensorfold-qwen38:zmerge4 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 2
  python3 pf2.py "$l" "zp-$l.jsonl" "$(( 600000 + RANDOM * 64 ))" | grep median
}
WARM=1 arm v6warm $M3
arm v6m3a $M3
arm v6m4a $M4
arm v6m4b $M4
arm v6m3b $M3
echo "##### done $(date -Is)"
