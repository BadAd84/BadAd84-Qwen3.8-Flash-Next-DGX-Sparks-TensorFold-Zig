#!/usr/bin/env bash
# profile_round.sh TAG CUMULATIVE.patch [name:ENV ...] - where a decode round's time goes on a rung.
# Builds TAG from the cumulative patch (which carries the TF_FLASHNEXT_ROUND_LOG instrumentation), then per arm a
# fresh boot at one stream (bf16, 131,072) with the log on, one decode pass (prose, then code), and the engine's
# "round log:" lines. The log drains the stream after every part, so its tok/s is not a speed result.
# WAIT=<marker> waits for that marker first; DONE=<marker> is touched at the end. Production is not restored here.
set -u
cd ~/work/target || exit 1
TAG=${1:?tag}; PATCH=${2:?cumulative patch}; shift 2
[ -n "${WAIT:-}" ] && for i in $(seq 1 900); do [ -f "$WAIT" ] && break; sleep 30; done
if ! docker image inspect "tensorfold-qwen38:$TAG" > /dev/null 2>&1; then
  dir=patches126/$TAG
  rm -rf "$dir" && mkdir -p "$dir" && cp "$PATCH" "$dir/0001-$TAG.patch"
  bash ./build_patches.sh "$TAG" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$TAG.log" 2>&1
  rc=$?
  echo "build $TAG rc=$rc $(grep -aE '^BUILT' "build-$TAG.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-$TAG.log" | sort -u | head -8 | cut -c1-180
  [ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$TAG" embedded > /dev/null 2>&1
fi
[ $# -eq 0 ] && set -- "log:"
for spec in "$@"; do
  name=${spec%%:*}; envs=${spec#*:}; [ "$name" = "$spec" ] && envs=""
  for C in ${STREAMS:-1}; do
    out="bench/rl-$TAG-$name/c$C"; mkdir -p "$out"
    ( cd ~/work/lanes/rpr/recipe && env $envs TF_FLASHNEXT_ROUND_LOG=1 PREPARE=0 IMAGE="tensorfold-qwen38:$TAG" CHECKPOINT=nvfp4 VISION=0 \
        TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL="$C" CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
        ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
    echo "=== rl-$TAG-$name C=$C env=[$envs]"
    python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "rl-$TAG-$name-c$C" "$C" "$HOME/work/target/$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-118
    docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
    grep -a "^round log:" "$out/logs.txt" | cut -c1-330
    ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  done
done
[ -n "${DONE:-}" ] && touch "$DONE"
