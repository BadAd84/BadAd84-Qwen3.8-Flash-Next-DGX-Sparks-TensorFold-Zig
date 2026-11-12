#!/usr/bin/env bash
# accepted.sh - the accepted rung (through old patch 0021) proven lever by lever with its own switches, on the same
# image, at bf16/131,072: the draft head lever on and off (ABBA), the n-gram reader, then the small upstream knobs
# stacked. Baseline arms bracket the set. Production restored at the end.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 400); do [ -f BISECTHC-DONE ] && break; sleep 30; done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
IMG=tensorfold-qwen38:r0021 bash ./patcheval.sh \
  "a1warm:" \
  "a1base:" \
  "a1headbf16:TF_FLASHNEXT_DRAFT_HEAD=bf16" \
  "a1base2:" \
  "a1headbf16b:TF_FLASHNEXT_DRAFT_HEAD=bf16" \
  "a1plain:TF_FLASHNEXT_GATHER_READ=0" \
  "a1plainstack:TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_ATTN_LANES=1 TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0 TF_FLASHNEXT_CHUNK=1024" \
  "a1base3:" > accepted.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch ACCEPTED-DONE
