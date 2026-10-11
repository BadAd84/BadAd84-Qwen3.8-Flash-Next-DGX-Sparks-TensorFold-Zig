#!/usr/bin/env bash
# zv7.sh: zmerge7 (zmerge6 + r3-slowboot retime1 + r3-ttft1k r3t-b + r3-sharedjoin sj3 + r3-promptcache whole states)
# verification, each step its own GPU-lock hold:
#  1. exactness: r3-promptcache's hold1 (golden, pcheck cold/replay/salt/extension shas, `tensorfold reuse`, the base's
#     cold replies) run on zmerge7 with zmerge7's env, a new RUNID;
#  2. decode: warm-up, m6 / m7 / m7 / m6 (golden + decode matrix + copy/rewrite + cold prefill, shared-32 per boot);
#  3. zab_rm sweep zmerge6 vs zmerge7 (golden + TTFT + RigMark), comparison zrm-m7.
set -u
cd ~/work/merge || exit 1
M6="PREPARE=0 TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/ots-mtp-fp8 TF_FLASHNEXT_CONFIDENCE=-0.15 TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1 TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05 TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1 TF_FLASHNEXT_COPY_SHARED=1 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_QSA_DECODE=12 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_FP8_TILE=1 TF_FLASHNEXT_INT4_PROMPT_GU=2 TF_FLASHNEXT_PREFILL_ROWS=4096"
X7="TF_FLASHNEXT_SHARED_EARLY=1 TF_FLASHNEXT_SHARED_EARLY_ROWS=6 TF_FLASHNEXT_SHARED_SLOT_LD=1"
BASE="$M6 IMAGE=tensorfold-qwen38:zmerge6 PATCHES=zmerge6"
OURS="$M6 $X7 IMAGE=tensorfold-qwen38:zmerge7 PATCHES=zmerge7"
# 1. exactness (hold1 with zmerge7's extra env)
sed -e 's#^M6=(#M6=(TF_FLASHNEXT_SHARED_EARLY=1 TF_FLASHNEXT_SHARED_EARLY_ROWS=6 TF_FLASHNEXT_SHARED_SLOT_LD=1 #' \
    -e 's#tee -a hold1.out#tee -a ~/work/merge/zv7-exact.out#' \
    -e 's#pc-ours1.json#pc-m7.json#; s#pc-base1.json#pc-m7base.json#; s#reuse-ours.log#reuse-m7.log#' \
    ~/work/lanes/r3-promptcache/hold1.sh > ~/work/merge/zv7-hold1.sh
# the M6 array in hold1 holds zmerge6's extras; the base boot uses zmerge6, which ignores the r3-sharedjoin knobs
flock -o ~/work/gpu.lock env RUNID=zv7a bash ~/work/merge/zv7-hold1.sh tensorfold-qwen38:zmerge7
echo "ZV7 exact done $(date -Is)" >> ~/work/merge/zv7.status
# 2. decode
cat > ~/work/merge/zv7-dec.sh <<EOF
#!/usr/bin/env bash
set -uo pipefail
cd ~/work/merge/v || exit 1
arm() {
  local l=\$1; shift
  ~/work/zarm.sh "\$l" 1 \$*
  grep -a "=== pass" ~/work/"zab-\$l.log"
  grep -ao "shared 32 rows[^;]*" ~/work/"zab-\$l.log" | head -1
  grep -ao "cost timing[^;]*" ~/work/"zab-\$l.log" | head -1
  python3 ~/work/zgold_cmp.py ~/work/zab3/zgold-base-c1.json ~/work/"zgold-\$l.json"
  [[ "\${WARM:-0}" == 1 ]] && return
  python3 zcopy.py "\$l" "zc-\$l.jsonl" 2
  python3 pf2.py "\$l" "zp-\$l.jsonl" "\$(( 970000 + RANDOM * 64 ))" | grep median
}
WARM=1 arm v14warm $M6 IMAGE=tensorfold-qwen38:zmerge7 $X7
arm v14m6a $M6 IMAGE=tensorfold-qwen38:zmerge6
arm v14m7a $M6 IMAGE=tensorfold-qwen38:zmerge7 $X7
arm v14m7b $M6 IMAGE=tensorfold-qwen38:zmerge7 $X7
arm v14m6b $M6 IMAGE=tensorfold-qwen38:zmerge6
echo "##### done \$(date -Is)"
EOF
flock -o ~/work/gpu.lock bash ~/work/merge/zv7-dec.sh > ~/work/merge/zv7-dec.log 2>&1
echo "ZV7 decode done $(date -Is)" >> ~/work/merge/zv7.status
# 3. TTFT + RigMark
RIGMARK_ID=zrm-m7 bash ~/work/bench/zab_rm.sh m7 "$BASE" "$OURS"
echo "ZV7 DONE $(date -Is)" >> ~/work/merge/zv7.status
