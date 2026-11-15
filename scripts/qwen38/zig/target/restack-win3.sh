#!/usr/bin/env bash
# win3.sh OUT CELL... - one GPU window on spark6 comparing our images cell by cell.
# CELL = name:streams:image:profile
#   profile fp8  : KV_DTYPE=fp8, CONTEXT=262144, TF_FLASHNEXT_KV_PAGES=4096 at 6 and 8 streams
#   profile bf16 : KV_DTYPE=bf16 (the default), CONTEXT=131072, no pages
# The arm's switches follow the image name: um96 (upstream main alone) runs the recipe's own settings;
# rs96 and rq7 run the FP4 launcher block (patches/main-964174ea05/README.md).
# Per cell: a fresh boot through the recipe, the boot log's self-check line, golden 6/6 at one stream,
# one decode pass of 512-token prose and code replies, /metrics counters. Production is restored at the end
# and /health is checked. The GPU lock is held for the whole window.
set -u
OUT=${1:?usage: win3.sh OUT CELL...}; shift
IMG_DIR=${IMG_DIR:-tensorfold-qwen38}
mkdir -p "$OUT"
FP4="TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8"
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/restore.log" 2>&1
  echo "=== restored $(date -Is) health $(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:8888/health)" | tee -a "$OUT/window.log"
}
cell() {
  local name=$1 c=$2 img=$3 prof=$4
  local out="$OUT/$name-c$c"; mkdir -p "$out"
  local kv="KV_DTYPE=fp8" ctx="CONTEXT=262144" pages=""
  local arm=""
  if [ "$prof" = bf16 ]; then kv="KV_DTYPE=bf16"; ctx="CONTEXT=131072"; fi
  [ "$c" -ge 6 ] && [ "$prof" = fp8 ] && pages="TF_FLASHNEXT_KV_PAGES=4096"
  case "$img" in um96) ;; *) arm=$FP4 ;; esac
  local t0=$(date +%s)
  ( cd ~/work/lanes/rpr/recipe && env $arm $pages PREPARE=0 IMAGE="$IMG_DIR:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native $kv $ctx PARALLEL="$c" HOST=127.0.0.1 MEM_CHECK=0 \
      WAIT_TIMEOUT=3600 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  local boot=$(( $(date +%s) - t0 ))
  echo "=== $name $prof C=$c boot ${boot}s $(date -Is)" | tee -a "$OUT/window.log"
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null |
    grep -E '^(TF_FLASHNEXT|TENSORFOLD)_' | sort > "$out/env.txt"
  grep -a -m1 "window self-check" "$out/logs.txt" | cut -c1-160 | tee -a "$OUT/window.log"
  grep -a -m1 -E "model .* GiB" "$out/logs.txt" | cut -c1-200 | tee -a "$OUT/window.log"
  if curl -s -o /dev/null -m 5 http://127.0.0.1:8888/health; then
    timeout 1200 python3 ~/work/qf_harness.py golden "$out/zgold.json" > "$out/golden.log" 2>&1
    echo "=== golden $(python3 -c "import json,sys;d=json.load(open('$out/zgold.json'));print(len(d))" 2>/dev/null)" | tee -a "$OUT/window.log"
    curl -s http://127.0.0.1:8888/metrics > "$out/metrics.txt" 2>/dev/null
    timeout 2400 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "w3-$name-$prof-c$c" "$c" "$out/dec.jsonl" 1 2>&1 |
      grep -a "^DEC" | cut -c1-200 | tee -a "$OUT/window.log"
    docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
    curl -s http://127.0.0.1:8888/metrics > "$out/metrics-after.txt" 2>/dev/null
  else
    echo "=== $name C=$c DID NOT SERVE" | tee -a "$OUT/window.log"
    grep -a -E "error|panic|refus|Unsupported|Unexpected|rgument" "$out/logs.txt" | head -6 | cut -c1-240 | tee -a "$OUT/window.log"
  fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  sleep 5
}
(
  flock 9
  echo "=== lock $(date -Is) image dir $IMG_DIR" | tee -a "$OUT/window.log"
  trap restore EXIT
  for spec in "$@"; do
    IFS=: read -r name c img prof <<< "$spec"
    cell "$name" "$c" "$img" "$prof"
  done
) 9>"$HOME/work/gpu.lock"
touch "$OUT/DONE"
echo "=== window done $(date -Is)" | tee -a "$OUT/window.log"
