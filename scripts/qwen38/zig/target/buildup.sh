#!/usr/bin/env bash
# buildup.sh STAGE - the catch-up measured in the owner's order (2026-11-11):
#   1  stock:  pristine TensorFold v1.2.6 (image up126), NO patches, the unmodified upstream recipe's own environment
#   2  tune:   the same pristine binary, one upstream knob changed per arm (only knobs the pristine engine has)
#   3  patch:  the accepted stack so far plus exactly ONE lever, each arm against the previous accepted image
# Every arm: a fresh boot a cell at C=1 and C=4, golden, one decode pass a kind. Stock cannot serve fp8 KV, and four
# bf16 windows of 262,144 tokens do not fit (32 GiB of cache), so every stage runs bf16 at 131,072 tokens until the
# kv8 lever is the one under test.
# A discarded warm-up arm leads every stage, and the stage's baseline is repeated at the end.
set -u
cd ~/work/target || exit 1
STAGE=${1:?stage 1, 2 or 3}
export KV_DTYPE=bf16 CONTEXT=131072
case "$STAGE" in
1)
  IMG=tensorfold-qwen38:up126 bash ./patcheval.sh "s1warm:" "s1stock:" "s1stock2:" > buildup1.log 2>&1
  ;;
2)
  IMG=tensorfold-qwen38:up126 bash ./patcheval.sh "s2warm:" "s2base:" \
    "s2attnlanes:TF_FLASHNEXT_ATTN_LANES=1" \
    "s2decgraph:TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0" \
    "s2chunk1024:TF_FLASHNEXT_CHUNK=1024" \
    "s2chunk2048:TF_FLASHNEXT_CHUNK=2048" \
    "s2greedywide8:TF_FLASHNEXT_GREEDY_WIDE=8" \
    "s2drafts8:TF_FLASHNEXT_DRAFTS=8" \
    "s2drafts4:TF_FLASHNEXT_DRAFTS=4" \
    "s2conf50:TF_FLASHNEXT_CONFIDENCE=0.50" \
    "s2conf70:TF_FLASHNEXT_CONFIDENCE=0.70" \
    "s2keeplate0:TF_FLASHNEXT_KEEP_LATE=0" \
    "s2sharedside0:TF_FLASHNEXT_SHARED_SIDE=0" \
    "s2gdnlanes0:TF_FLASHNEXT_GDN_LANES=0" \
    "s2gdnfused:TF_FLASHNEXT_GDN_FUSED=1" \
    "s2hcfuse0:TF_FLASHNEXT_HC_FUSE=0" \
    "s2firstearly:TF_FLASHNEXT_FIRST_EARLY=1" \
    "s2base2:" > buildup2.log 2>&1
  ;;
3)
  # ACCEPTED is the environment stage 2 proved; each arm names its image.
  A=${ACCEPTED:-}
  IMG=tensorfold-qwen38:up126 bash ./patcheval.sh "s3warm:$A" "s3stock:$A" > buildup3.log 2>&1
  IMG=tensorfold-qwen38:stack126a bash ./patcheval.sh "s3rows:$A" >> buildup3.log 2>&1
  IMG=tensorfold-qwen38:up126 bash ./patcheval.sh "s3stock2:$A" >> buildup3.log 2>&1
  ;;
esac
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== stage $STAGE done, production restored $(date -Is)"
touch "$HOME/work/target/BUILDUP$STAGE-DONE"
