#!/usr/bin/env bash
# mverify.sh (spark6, run under flock ~/work/gpu.lock): the merged image against stock zots5 (0101+0102+0104, -0.15).
# A discarded warm-up boot first (the first boot after a lock handover runs slow), then 2 cycles base/merged,
# merged/base. Each boot: golden + decode matrix (zarm.sh, 1 pass) then copy/rewrite + cold prefill with fresh text
# (zarm2.sh). Logs in ~/work/merge/v/.
set -uo pipefail
V=~/work/merge/v; mkdir -p "$V"; cd "$V" || exit 1
sed "s/(8000, 32000, 128000)/(8000, 32000)/; s/range(3)/range(2)/" ~/work/prefill_fresh.py > pf2.py; cp ~/work/zarm.sh ~/work/zarm2.sh ~/work/zcopy.py ~/work/prefill_fresh.py ~/work/qf_harness.py ~/work/qf_run.py ~/work/zgold_cmp.py . 2>/dev/null
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15"
BASE="$COMMON IMAGE=tensorfold-qwen38:zots5"
MERGED="$COMMON IMAGE=tensorfold-qwen38:zmerge1 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep"
echo "##### start $(date -Is)"
arm() {  # label env...
  local l=$1; shift
  # shellcheck disable=SC2086
  ./zarm.sh "$l" 1 $* ; grep -a "=== pass\|window 1 rows" "zab-$l.log"
  python3 zgold_cmp.py ~/work/zab3/zgold-base-c1.json "zgold-$l.json"
  # copy/rewrite + fresh prefill on the already-running server (zarm2 would restart it: run its parts directly)
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 3
  python3 pf2.py "$l" "zp-$l.jsonl" "$(( 300000 + RANDOM * 64 ))" | grep median
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "n-gram table on the host\|window\b" | head -2
}
WARM=1 arm warm $BASE
arm b1 $BASE
arm m1 $MERGED
arm m2 $MERGED
arm b2 $BASE
echo "##### done $(date -Is)"
