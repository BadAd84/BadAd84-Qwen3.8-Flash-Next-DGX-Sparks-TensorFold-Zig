#!/usr/bin/env bash
# knobsweep.sh - step one of the catch-up: profile the performance knobs the NEW engine already has (upstream v1.2.6
# plus our build), before touching the patches. Each arm is one knob setting at C=1 and C=4 with the target's
# settings (nvfp4, fp8 KV, 262,144 tokens), golden, one decode pass and the boot self-check. `base` is the reference.
set -u
cd ~/work/target || exit 1
bash ./patcheval.sh \
  "base:" \
  "decgraph:TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0" \
  "attnlanes:TF_FLASHNEXT_ATTN_LANES=1" \
  "chunk1024:TF_FLASHNEXT_CHUNK=1024" \
  "chunk512:TF_FLASHNEXT_CHUNK=512" \
  "chunksolo1536:TF_FLASHNEXT_CHUNK_SOLO=1536" \
  "windowrows32:TF_FLASHNEXT_WINDOW_ROWS=32" \
  "greedywide8:TF_FLASHNEXT_GREEDY_WIDE=8" \
  "fact128:TF_FLASHNEXT_FACT_ROWS=128" \
  "readout128:TF_FLASHNEXT_READOUT_ROWS=128" \
  "nodrafts:TF_FLASHNEXT_DRAFTS=0" \
  "nowgraph:TF_FLASHNEXT_WINDOW_GRAPH=0"
echo "=== knob sweep done $(date -Is)"
touch "$HOME/work/target/KNOBSWEEP-DONE"
