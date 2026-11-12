#!/usr/bin/env bash
# copy_arm.sh name:image:ENV ... - the copy workload of a rung: a fresh boot at one stream (bf16, 131,072), then
# zcopy.py's two replies (a ~1,800-token text repeated verbatim, and rewritten with one word changed), three runs
# each. This is where the rows lever (wider copy windows) and the resync lever show; a 512-token prose or code reply
# has almost nothing to copy. Prints the two medians and the replies' shas. No restore.
set -u
cd ~/work/target || exit 1
for spec in "$@"; do
  name=${spec%%:*}; rest=${spec#*:}; img=${rest%%:*}; envs=${rest#*:}; [ "$img" = "$rest" ] && envs=""
  out="bench/cp-$name"; mkdir -p "$out"; rm -f "$out/copy.jsonl"
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "CP $name: image $img missing"; continue; }
  ( cd ~/work/lanes/rpr/recipe && env $envs PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  ( cd ~/work && python3 zcopy.py "cp-$name" "$HOME/work/target/$out/copy.jsonl" 3 ) > "$out/copy.txt" 2>&1
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  printf 'CP %-12s %s | %s | shas %s | check %s [%s] %s\n' "$name" \
    "$(grep -a ' copy: ' "$out/copy.txt" | sed 's/.*copy: //' | cut -c1-60)" \
    "$(grep -a ' rewrite: ' "$out/copy.txt" | sed 's/.*rewrite: //' | cut -c1-60)" \
    "$(python3 -c "import json,sys;print(','.join(sorted({(json.loads(l).get('sha') or '-')[:8]+':'+json.loads(l)['kind'][0] for l in open(sys.argv[1])})))" "$out/copy.jsonl" 2>/dev/null)" \
    "$(grep -aoE 'self-check: [0-9]+ of [0-9]+' "$out/logs.txt" | head -1 | sed 's/self-check: //')" "$img" "$envs"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
done
