#!/usr/bin/env bash
# post_sweep.sh - after the overnight sweep: stock RigMark with the stock metadata, then the boot self-check read
# with each prompt-path knob inverted (the suspects for its 0-of-2080 result), then the production serve restored.
set -u
cd "$HOME/work/target" || exit 1
while [ ! -f BENCH-DONE ]; do sleep 60; done
echo "=== sweep done, post steps start $(date -Is)"
probe() {
  local name=$1; shift
  echo "--- probe $name $(date -Is)"
  ( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
  ( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE=tensorfold-qwen38:stack126 CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=3 CONTEXT=131072 HOST=127.0.0.1 "$@" \
      ./start.sh restart </dev/null ) > "/tmp/probe-$name.log" 2>&1
  echo "probe $name rc=$?"
  docker logs qwen38-flash-next-tf 2>&1 | grep -aE "self-check|copy windows|prompt=" | tail -3
}
echo "--- stock rigmark $(date -Is)"
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE=tensorfold-qwen38:up126 CHECKPOINT=nvfp4 VISION=0 \
    TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=6 CONTEXT=131072 HOST=127.0.0.1 ./start.sh restart </dev/null ) \
  > /tmp/probe-stockrig.log 2>&1
RIGMARK_DIR="$HOME/rigmark" bash "$HOME/work/bench/rigmark_run.sh" stock-final "ots126-stock-final" \
  "$HOME/work/bench/rigmark/metadata-zig-stock.json" > "$HOME/work/target/bench/stock/rigmark-final.log" 2>&1
echo "stock rigmark rc=$? $(grep -aE '^summary|^exit' "$HOME/work/target/bench/stock/rigmark-final.log" | tail -1 | cut -c1-200)"
probe default
probe sync TF_FLASHNEXT_PROMPT_SYNC=1
probe chunk TF_FLASHNEXT_CHUNK=1024
probe headbf16 TF_FLASHNEXT_DRAFT_HEAD=bf16
probe hc2 TF_FLASHNEXT_PROMPT_HC2=1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -4
echo "=== production restored $(date -Is)"
touch "$HOME/work/target/POST-DONE"
