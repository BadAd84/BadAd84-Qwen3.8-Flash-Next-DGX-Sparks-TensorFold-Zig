#!/usr/bin/env bash
# bisect.sh NAME - build tensorfold-qwen38:NAME from the patch subset in ~/work/target/sub-NAME (plus 0028 when the
# subset needs its compile fixes), relabel it, boot it through the campaign recipe and send one request; report
# PASS/FAIL with the self-check line and the recipe's verdict.
set -u
NAME=${1:?name}
SUB=$HOME/work/target/sub-$NAME
LOG=$HOME/work/target/bisect-$NAME.log
{
  echo "=== subset $NAME $(date -Is): $(ls "$SUB"/*.patch | wc -l) patches"
  if ! docker image inspect "tensorfold-qwen38:$NAME" > /dev/null 2>&1; then
    bash "$HOME/work/target/build_patches.sh" "$NAME" git://192.168.99.16/up-pr/tf \
      6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$SUB" > "$HOME/work/target/build-$NAME.log" 2>&1 \
      || { echo "BUILD FAILED"; grep -aE "error:" "$HOME/work/target/build-$NAME.log" | head -5; exit 1; }
  fi
  L=$(docker image inspect "tensorfold-qwen38:$NAME" --format '{{index .Config.Labels "tf.kernels"}}')
  [ "$L" = embedded ] || bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$NAME" embedded > /dev/null 2>&1
  ( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
  ( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="tensorfold-qwen38:$NAME" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=3 CONTEXT=131072 HOST=127.0.0.1 \
      ./start.sh restart </dev/null ) > "$HOME/work/target/boot-$NAME.log" 2>&1
  rc=$?
  echo "boot rc=$rc"
  grep -aE "Server answered|LIVE|ERROR|error:|self-check|copy windows|needs [0-9]" "$HOME/work/target/boot-$NAME.log" | tail -6
  echo "=== $NAME done $(date -Is)"
} | tee "$LOG"
