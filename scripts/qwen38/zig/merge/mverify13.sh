#!/usr/bin/env bash
# mverify13.sh (under the GPU lock): the clean upstream stack zpr3-stack (recipe patches 0010-0024, settings renamed)
# against zmerge6, warm-up then m6 / pr / pr / m6 (golden + decode matrix + copy/rewrite + cold prefill), then the
# batch-3 packages' mutants.sh on zpr3-stack (their exit codes).
set -uo pipefail
cd ~/work/merge/v || exit 1
COMMON="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15"
M6="$COMMON IMAGE=tensorfold-qwen38:zmerge6 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_COPY_SHARED=1 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_QSA_DECODE=12 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_FP8_TILE=1 TF_FLASHNEXT_INT4_PROMPT_GU=2 TF_FLASHNEXT_PREFILL_ROWS=4096"
PR="$COMMON IMAGE=tensorfold-qwen38:zpr3-stack TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_COPY_RESYNC=1 TF_FLASHNEXT_COPY_RAMP=jump TF_FLASHNEXT_COPY_MISS=keep TF_FLASHNEXT_COPY_SHARED=1 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_BATCH_DRAWS=1 TF_FLASHNEXT_BATCH_WINDOWS=1 TF_FLASHNEXT_FP8_FUSED_SPLIT=4 TF_FLASHNEXT_HEAD_ROW_TILES=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_REDUCE_ACT=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_DRAFT_PROPOSE=0.05 TF_FLASHNEXT_DRAFT_CONTINUE=0.20 TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_QSA_SELECT=1 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_FP8_PROMPT_TILES=1 TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1 TF_FLASHNEXT_PREFILL_ROWS=4096"
echo "##### start $(date -Is)"
arm() {
  local l=$1; shift
  # shellcheck disable=SC2086
  ~/work/zarm.sh "$l" 1 $*
  grep -a "=== pass" ~/work/"zab-$l.log"
  grep -ao "shared 32 rows[^;]*" ~/work/"zab-$l.log" | head -1
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-$l.json"
  docker logs qwen38-flash-next-tf 2>&1 | grep -av "│" | grep -a "hc q12\|qsa\|prompt tiles\|gate/up\|prefill rows\|fp8" | head -6
  [[ "${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "$l" "zc-$l.jsonl" 2
  python3 pf2.py "$l" "zp-$l.jsonl" "$(( 950000 + RANDOM * 64 ))" | grep median
}
WARM=1 arm v13warm $M6
arm v13m6a $M6
arm v13pra $PR
arm v13prb $PR
arm v13m6b $M6
docker stop qwen38-flash-next-tf >/dev/null 2>&1
for d in zig-pr-readout-12bit zig-pr-indexer-select zig-pr-prompt-tiles; do
  echo "##### mutants $d"
  bash ~/work/zpr3/mutants/$d.sh tensorfold-qwen38:zpr3-stack 2>&1 | tail -6
  echo "exit $?"
done
echo "##### done $(date -Is)"
