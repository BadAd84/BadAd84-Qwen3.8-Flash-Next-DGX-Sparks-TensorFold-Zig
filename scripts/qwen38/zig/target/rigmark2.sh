#!/usr/bin/env bash
# rigmark2.sh - RigMark for both arms with the FP4 checkpoint templates, then the production serve restored.
set -u
cd "$HOME/work/target" || exit 1
run() {
  local arm=$1 img=$2 kv=$3 tpl=$4
  echo "--- rigmark $arm $(date -Is)"
  ( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
  ( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="$img" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
      KV_DTYPE="$kv" PARALLEL=6 CONTEXT=131072 HOST=127.0.0.1 ./start.sh restart </dev/null ) > "/tmp/rig-$arm.boot.log" 2>&1
  grep -a "LIVE\|rror" "/tmp/rig-$arm.boot.log" | tail -1
  RIGMARK_DIR="$HOME/rigmark" bash "$HOME/work/bench/rigmark_run.sh" "$arm" "ots126-$arm-fp4" "$tpl" \
    > "bench/$arm/rigmark-fp4.log" 2>&1
  echo "rigmark $arm rc=$? $(grep -aE '^summary|^exit' "bench/$arm/rigmark-fp4.log" | tail -1 | cut -c1-180)"
}
run stock tensorfold-qwen38:up126 bf16 "$HOME/work/bench/rigmark/metadata-zig-fp4-stock.json"
run full tensorfold-qwen38:stack126 fp8 "$HOME/work/bench/rigmark/metadata-zig-fp4.json"
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -3
echo "=== production restored $(date -Is)"
touch "$HOME/work/target/RIG2-DONE"
