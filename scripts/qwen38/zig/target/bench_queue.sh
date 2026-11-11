#!/bin/bash
# bench_queue.sh - the overnight 1.2.6 sweep on spark6: every arm gets a fresh boot per level, under the box's GPU
# lock, and the serve is restored (or left serving the full stack) on every exit path.
#   ARMS: "name image kv context levels rigmark" one per line, e.g.
#     stock tensorfold-qwen38:up126 bf16 131072 1,2,4,6 1
#     a1rows tensorfold-qwen38:a1 bf16 131072 1,2,4 0
# Run detached: (setsid nohup ./bench_queue.sh > bench.log 2>&1 < /dev/null &)
set -u
cd "$HOME/work/target" || exit 1
trap 'echo "=== queue exit $(date -Is)"; touch "$HOME/work/target/BENCH-DONE"' EXIT
exec 9>~/work/gpu.lock
flock 9 || exit 1
while read -r ARM IMG KV CTX LEVELS RIG; do
  [ -z "${ARM:-}" ] && continue
  echo "=== arm $ARM image $IMG kv $KV ctx $CTX levels $LEVELS rigmark $RIG $(date -Is)"
  for C in ${LEVELS//,/ }; do
    echo "--- cell $ARM C=$C $(date -Is)"
    IMG="$IMG" KV_DTYPE="$KV" CONTEXT="$CTX" bash ./bench_arm.sh "$ARM" "$C"
    echo "cell $ARM C=$C rc=$? $(grep -aE '^BOOT seconds|^GOLD exit|^PROBE|BOOT FAILED' "bench/$ARM/c$C/arm.log" | tr '\n' ' ')"
  done
  if [ "${RIG:-0}" = 1 ]; then
    echo "--- rigmark $ARM $(date -Is)"
    IMG_ID=$(docker image inspect "$IMG" --format '{{.Id}}' | cut -c8-19)
    ( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="$IMG" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
        KV_DTYPE="$KV" PARALLEL=6 CONTEXT="$CTX" HOST=127.0.0.1 ./start.sh restart </dev/null ) 2>&1 | grep -a "LIVE\|rror" | head -3
    TEMPLATE=$HOME/work/bench/rigmark/metadata-zig-ours.json
    [ "$ARM" = stock ] && TEMPLATE=$HOME/work/bench/rigmark/metadata-zig-stock.json
    RIGMARK_DIR="$HOME/rigmark" bash "$HOME/work/bench/rigmark_run.sh" "$ARM" "ots126-$ARM" \
      "$TEMPLATE" > "bench/$ARM/rigmark.log" 2>&1
    echo "rigmark $ARM rc=$? $(grep -aE '^summary|^exit' "bench/$ARM/rigmark.log" | tail -1 | cut -c1-200)"
  fi
done < "${ARMS_FILE:-$HOME/work/target/arms.txt}"
echo "=== sweep done $(date -Is)"
