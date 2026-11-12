#!/usr/bin/env bash
# probe_rung.sh IMAGE name:ENV... - boot a rung with a lever setting and report whether the recipe's own smoke
# request survives, plus the self-check line. Stops the serve after each probe; restores production at the end.
set -u
IMG=${1:?image tag}; shift
cd ~/work/lanes/rpr/recipe || exit 1
( ./stop.sh ) > /dev/null 2>&1
for spec in "$@"; do
  name=${spec%%:*}; envs=${spec#*:}; [ "$name" = "$spec" ] && envs=""
  ( env $envs PREPARE=0 IMAGE="tensorfold-qwen38:$IMG" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
      KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 ./start.sh restart </dev/null ) > "/tmp/probe-$name.log" 2>&1
  verdict=OK
  grep -q "smoke test request failed\|ILLEGAL_ADDRESS\|panic\|BOOT FAILED" "/tmp/probe-$name.log" && verdict=FAULT
  docker logs qwen38-flash-next-tf 2>&1 | grep -q "ILLEGAL_ADDRESS\|panic" && verdict=FAULT
  printf "%-14s %-6s [%s] %s\n" "$name" "$verdict" "$envs" "$(docker logs qwen38-flash-next-tf 2>&1 | grep -aoE "self-check: [0-9]+ of [0-9]+" | head -1)"
  ( ./stop.sh ) > /dev/null 2>&1
done
[ "${NOPROD:-0}" = 1 ] || ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
