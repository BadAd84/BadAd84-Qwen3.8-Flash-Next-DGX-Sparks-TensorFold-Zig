#!/usr/bin/env bash
# mverify2.sh (under the GPU lock): the merged image's copy-policy settings vs stock. Warm-up boot discarded, then
# base, resync off, resync gated KEPT=4, resync gated TRIES=1, base. Each: golden + decode matrix (zarm.sh, writes
# into ~/work) + copy/rewrite (zcopy.py). Log ~/work/merge/mverify2.log.
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15"
BASE="$COMMON IMAGE=tensorfold-qwen38:zots5"
M="$COMMON IMAGE=tensorfold-qwen38:zmerge1 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64"
RS="TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 2
}
WARM=1 arm v2warm $BASE
arm v2b1 $BASE
arm v2off $M
arm v2k4 $M $RS TENSORFOLD_COPY_RESYNC_KEPT=4
arm v2t1 $M $RS TENSORFOLD_COPY_RESYNC_TRIES=1
arm v2b2 $BASE
echo "##### done $(date -Is)"
