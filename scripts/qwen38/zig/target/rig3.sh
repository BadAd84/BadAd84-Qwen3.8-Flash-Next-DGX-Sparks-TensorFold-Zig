#!/usr/bin/env bash
# rig3.sh - RigMark for the upstream-1.2.6 arm with a neutral FP4 template (no stock/ours arm check), then the
# production serve restored.
set -u
cd "$HOME/work/target" || exit 1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE=tensorfold-qwen38:up126 CHECKPOINT=nvfp4 VISION=0 \
    TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=6 CONTEXT=131072 HOST=127.0.0.1 ./start.sh restart </dev/null ) \
  > /tmp/rig3.boot.log 2>&1
grep -a "LIVE\|rror" /tmp/rig3.boot.log | tail -1
RIGMARK_DIR="$HOME/rigmark" bash "$HOME/work/bench/rigmark_run.sh" stock "ots126-stock-fp4" \
  "$HOME/work/bench/rigmark/metadata-zig-fp4-neutral.json" > bench/stock/rigmark-fp4b.log 2>&1
echo "rigmark stock rc=$? $(grep -aE '^summary|^exit' bench/stock/rigmark-fp4b.log | tail -1 | cut -c1-200)"
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -3
echo "=== production restored $(date -Is)"
touch "$HOME/work/target/RIG3-DONE"
