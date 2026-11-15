#!/usr/bin/env bash
# restack2-win.sh OUT CELL... - one GPU window on spark6: the re-seated package (A) against it without 0004 (B).
# CELL = name:streams:image. Every cell: fp8 KV at 262,144 (TF_FLASHNEXT_KV_PAGES=4096 at 6 and 8 streams), the FP4
# launcher block (patches/1.2.7/README.md) on top of the recipe's own settings, a fresh boot through the recipe's
# start.sh bound to 127.0.0.1 (no outside traffic reaches it), the boot log's self-check line, golden 6/6 against the
# previous window's replies, one decode pass of 512-token prose and code replies, /metrics before and after.
# The GPU lock is taken FIFO (flock -w 43200) and held for the whole window; no child keeps the lock's descriptor.
# Production is restored at the end (qwen6-start-prod.sh) and /health is checked.
set -u
OUT=${1:?usage: restack2-win.sh OUT CELL...}; shift
REF=$HOME/work/restack2/win/ref-win2-rs96-c1-zgold.json
mkdir -p "$OUT"
FP4="TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1 TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8"
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh 9>&- ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null 9>&- ) > "$OUT/restore.log" 2>&1
  local h=000
  for _ in $(seq 1 60); do
    h=$(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:8888/health)
    [ "$h" = 200 ] && break
    sleep 10
  done
  echo "=== restored $(date -Is) health $h" | tee -a "$OUT/window.log"
}
cell() {
  local name=$1 c=$2 img=$3
  local out="$OUT/$name-c$c"; mkdir -p "$out"
  local pages=""
  [ "$c" -ge 6 ] && pages="TF_FLASHNEXT_KV_PAGES=4096"
  echo "=== $name C=$c gpu $(nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader 2>/dev/null) $(date -Is)" | tee -a "$OUT/window.log"
  local t0=$(date +%s)
  ( cd ~/work/lanes/rpr/recipe && env $FP4 $pages PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 CONTEXT=262144 PARALLEL="$c" HOST=127.0.0.1 MEM_CHECK=0 \
      WAIT_TIMEOUT=3600 ./start.sh restart </dev/null 9>&- ) > "$out/boot.log" 2>&1
  echo "=== $name $img C=$c boot $(( $(date +%s) - t0 ))s" | tee -a "$OUT/window.log"
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null |
    grep -E '^(TF_FLASHNEXT|TENSORFOLD)_' | sort > "$out/env.txt"
  grep -a -m1 "window self-check" "$out/logs.txt" | cut -c1-160 | tee -a "$OUT/window.log"
  if curl -s -o /dev/null -m 5 http://127.0.0.1:8888/health; then
    timeout 1200 python3 ~/work/qf_harness.py golden "$out/zgold.json" > "$out/golden.log" 2>&1 9>&-
    python3 "$HOME/work/restack2/win/golden.py" "$REF" "$out/zgold.json" 2>&1 | sed "s|^|=== golden |" | tee -a "$OUT/window.log"
    curl -s http://127.0.0.1:8888/metrics > "$out/metrics.txt" 2>/dev/null
    timeout 2400 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "r2-$name-c$c" "$c" "$out/dec.jsonl" 1 2>&1 9>&- |
      grep -a "^DEC" | cut -c1-200 | tee -a "$OUT/window.log"
    docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
    curl -s http://127.0.0.1:8888/metrics > "$out/metrics-after.txt" 2>/dev/null
  else
    echo "=== $name C=$c DID NOT SERVE" | tee -a "$OUT/window.log"
    grep -a -E "error|panic|refus|Unsupported|Unexpected|rgument" "$out/logs.txt" | head -6 | cut -c1-240 | tee -a "$OUT/window.log"
  fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh 9>&- ) > /dev/null 2>&1
  sleep 5
}
(
  echo "=== queued $(date -Is)" | tee -a "$OUT/window.log"
  flock -w 43200 9 || { echo "=== lock wait timed out $(date -Is)" | tee -a "$OUT/window.log"; exit 1; }
  echo "=== lock $(date -Is)" | tee -a "$OUT/window.log"
  trap restore EXIT
  for spec in "$@"; do
    IFS=: read -r name c img <<< "$spec"
    cell "$name" "$c" "$img"
  done
) 9>"$HOME/work/gpu.lock"
touch "$OUT/DONE"
echo "=== window done $(date -Is)" | tee -a "$OUT/window.log"
