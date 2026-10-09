#!/usr/bin/env bash
# mverify7.sh (under the GPU lock): the prose stop-rule configs on zmerge4 + the calibrated rule (image zstack; with the
# cum rule off it is zmerge4). Arms: m4 (zmerge4's W6 split rule), k10 (m4 + top-10 MTP routing), stack (calibrated
# cum T=0.20 + Zig's own d4k10 table + top-10 + int4 draft head). Warm-up, then m4, stack, k10, k10, stack, m4.
# Each boot: golden + decode matrix (zarm.sh) + 6 one-client prose prompts (prose-glm pm.py, PM_N=6).
set -uo pipefail
cd ~/work/merge/v || exit 1
cp ~/work/lanes/prose-glm/pm.py pmz.py
COMMON="PREPARE=0 IMAGE=tensorfold-qwen38:zstack TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_DRAFT_INT4=1"
M4="$COMMON TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7"
K10="$M4 TF_FLASHNEXT_MTP_TOPK=10"
CAL=$(cut -d= -f2- ~/work/lanes/prose-glm/cal-d4k10.env | tr -d '\n')
STACK="$COMMON TF_FLASHNEXT_CHAIN_RULE=cum TF_FLASHNEXT_CHAIN_T=0.20 TF_FLASHNEXT_CAL=$CAL TF_FLASHNEXT_MTP_TOPK=10"
echo "##### start $(date -Is)  cal=${CAL:0:40}"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -a "chain rule\|cum\|w6 \|routed experts\|TOPK" | head -3
  [[ "${WARM:-0}" == 1 ]] && return
  PM_N=6 python3 pmz.py "$l" "pm-$l.jsonl" | tail -2
}
WARM=1 arm v7warm $M4
arm v7m4a $M4
arm v7stacka $STACK
arm v7k10a $K10
arm v7k10b $K10
arm v7stackb $STACK
arm v7m4b $M4
echo "##### done $(date -Is)"
