#!/usr/bin/env bash
# finishall.sh - the remaining evaluation, linear and marker-free:
#   1. the prompt-path arms the confirmation batch never reached, plus its baseline
#   2. the drafter switched off properly (DRAFTS=0, which adds --no-drafts)
#   3. the 31-patch image, then the row cache through the page cache against plain and O_DIRECT
#   4. the stacked arm: every micro-gain together, ABBA against its own baseline
#   5. production restored
set -u
cd ~/work/target || exit 1
echo "=== 1. prompt-path arms $(date -Is)"
bash ./patcheval.sh "warmq:" "qbase:" \
  "promptshared0:TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0" \
  "promptsync1:TF_FLASHNEXT_PROMPT_SYNC=1" \
  "headpiece0:TF_FLASHNEXT_HEAD_PIECE=0" \
  "qbase2:" > finish1.log 2>&1

echo "=== 2. the drafter off $(date -Is)"
bash ./patcheval.sh "draftsoff:DRAFTS=0" "dbase:" > finish2.log 2>&1

echo "=== 3. the 31-patch image $(date -Is)"
bash ./build_patches.sh stack126v2 git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 patches126 > build-v2.log 2>&1
echo "build rc=$? $(grep -aE '^BUILT|error:' build-v2.log | head -2)"
bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:stack126v2 embedded > /dev/null 2>&1
IMG=tensorfold-qwen38:stack126v2 bash ./patcheval.sh \
  "v2base:" "v2buffered:TF_FLASHNEXT_GATHER_DIRECT=0" "v2plain:TF_FLASHNEXT_GATHER_READ=0" > finish3.log 2>&1

echo "=== 4. the stacked arm $(date -Is)"
IMG=tensorfold-qwen38:stack126v2 bash ./patcheval.sh \
  "stkbase:" \
  "stka:TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_ATTN_LANES=1 TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0 TF_FLASHNEXT_CHUNK=1024" \
  "stkbase2:" \
  "stkb:TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_ATTN_LANES=1 TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0 TF_FLASHNEXT_CHUNK=1024" > finish4.log 2>&1

( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== production $(date -Is)"
touch "$HOME/work/target/FINISH-DONE"
