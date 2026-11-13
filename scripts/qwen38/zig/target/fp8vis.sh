#!/usr/bin/env bash
# fp8vis.sh - patch 0015's remaining checks on spark6: the fp8 device test (tf-cuda-test flashnext-kv8) in image fp8pg2
# and in v16 (the series before 0015), then vision on with fp8 KV and a 262,144 window: one boot with every stream on
# pool pages, one unpaged, the same image request to each at temperature 0 (fp8vis.py). Takes the GPU lock first and
# restores production inside it.
set -u
cd ~/work/target || exit 1
LOG=fp8vis.log
: > "$LOG"
(
  flock -w 7200 9 || { echo "fp8vis: the GPU lock is held" >> "$LOG"; exit 1; }
  echo "=== lock $(date -Is)" >> "$LOG"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  for img in fp8pg2 v16; do
    echo "=== device test flashnext-kv8 in $img $(date -Is)" >> "$LOG"
    docker run --rm --gpus all --ipc=host --entrypoint sh "tensorfold-qwen38:$img" -c \
      'b=$(command -v tf-cuda-test || find / -xdev -name tf-cuda-test -type f 2>/dev/null | head -1); echo "runner: ${b:-none}"; [ -n "$b" ] || exit 3; cd "$(dirname "$b")/.." 2>/dev/null; "$b" flashnext-kv8; echo "exit $?"' \
      >> "$LOG" 2>&1
  done
  for arm in "vpa:TF_FLASHNEXT_KV_PAGES=4096 TF_FLASHNEXT_KV_PAGES_ALL=1" "vu:"; do
    name=${arm%%:*}; envs=${arm#*:}
    echo "=== vision $name env=[$envs] $(date -Is)" >> "$LOG"
    ( cd ~/work/lanes/rpr/recipe && env $envs PREPARE=0 IMAGE=tensorfold-qwen38:fp8pg2 CHECKPOINT=nvfp4 VISION=1 \
        TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=2 CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 \
        ./start.sh restart </dev/null ) > "bench/vis-$name.boot" 2>&1
    docker logs qwen38-flash-next-tf > "bench/vis-$name.logs" 2>&1
    grep -a "self-check: \|KV page groups\|streams at once\|stream at once\|vision\|tower\|image\|error" \
      "bench/vis-$name.logs" "bench/vis-$name.boot" | cut -c1-300 | head -12 >> "$LOG"
    python3 fp8vis.py "bench/vis-$name.json" >> "$LOG" 2>&1
    docker logs qwen38-flash-next-tf 2>&1 | grep -a "ended chatcmpl\|error" | tail -3 | cut -c1-250 >> "$LOG"
    ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  done
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1 >> "$LOG"
  echo "=== restored $(date -Is)" >> "$LOG"
) 9> ~/work/gpu.lock
python3 -c "import json; a=json.load(open('bench/vis-vpa.json')); b=json.load(open('bench/vis-vu.json')); print('PAGED-vs-UNPAGED image reply identical:', a.get('content') is not None and a.get('content') == b.get('content'))" >> "$LOG" 2>&1
touch FP8VIS-DONE
