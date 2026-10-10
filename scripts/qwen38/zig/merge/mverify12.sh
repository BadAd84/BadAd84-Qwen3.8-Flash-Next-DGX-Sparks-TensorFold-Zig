#!/usr/bin/env bash
# mverify12.sh (under the GPU lock): TF_FLASHNEXT_PF1 on zmerge6: base / 31 / 28 (31 without the hc-down bit 1,
# whose bf16 rows the 12-bit read-out path no longer reads) / 28 / 31 / base after a warm-up. Each: golden + one
# decode-matrix pass; the boot's shared-32 cost is printed so slow boots can be set aside.
set -uo pipefail
cd ~/work/merge/v || exit 1
M6="PREPARE=0 IMAGE=tensorfold-qwen38:zmerge6 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_COPY_SHARED=1 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_QSA_DECODE=12 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_FP8_TILE=1 TF_FLASHNEXT_INT4_PROMPT_GU=2 TF_FLASHNEXT_PREFILL_ROWS=4096"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  grep -ao "shared 32 rows[^,;]*" ~/work/"zab-$l.log" | head -1
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "pf1:\|hc q12" | head -2
}
WARM=1 arm v12warm $M6
arm v12b0a $M6
arm v12p31a $M6 TF_FLASHNEXT_PF1=31
arm v12p28a $M6 TF_FLASHNEXT_PF1=28
arm v12p28b $M6 TF_FLASHNEXT_PF1=28
arm v12p31b $M6 TF_FLASHNEXT_PF1=31
arm v12b0b $M6
echo "##### done $(date -Is)"
