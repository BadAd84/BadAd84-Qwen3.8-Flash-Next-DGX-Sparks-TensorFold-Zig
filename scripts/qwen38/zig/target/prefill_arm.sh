#!/usr/bin/env bash
# prefill_arm.sh name:image:ENV ... - cold prompt time of a rung: a fresh boot at one stream (bf16, 131,072), then
# ttft.py's cold 8k and 32k prompts, thinking off, idle, three reps each (every prompt salted, so none is cached).
# Prints one line an arm with the two medians. Output in bench/pf-<name>/. Stops the serve at the end, no restore.
set -u
cd ~/work/target || exit 1
# a HOLD file parks the arms: a diagnostic run borrows the box between a stage's builds and its timed arms
while [ -f HOLD ]; do sleep 20; done
for spec in "$@"; do
  name=${spec%%:*}; rest=${spec#*:}; img=${rest%%:*}; envs=${rest#*:}; [ "$img" = "$rest" ] && envs=""
  out="bench/pf-$name"; mkdir -p "$out"
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "PF $name: image $img missing"; continue; }
  ( cd ~/work/lanes/rpr/recipe && env $envs PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  python3 ~/work/bench/ttft.py 8888 --sizes 8k,32k --thinking off --warm-add 0 --loads idle --reps 3 > "$out/ttft.txt" 2>&1
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  m8=$(grep -a "^summary cold8k-off idle" "$out/ttft.txt" | grep -aoE "ttft med [0-9.]+" | awk '{print $3}')
  m32=$(grep -a "^summary cold32k-off idle" "$out/ttft.txt" | grep -aoE "ttft med [0-9.]+" | awk '{print $3}')
  printf 'PF %-14s 8k %-7s 32k %-7s errors %s gpu %s [%s] %s\n' "$name" "${m8:--}" "${m32:--}" "$(grep -ac '^error' "$out/ttft.txt")" \
    "$(nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' ')" "$img" "$envs"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
done
