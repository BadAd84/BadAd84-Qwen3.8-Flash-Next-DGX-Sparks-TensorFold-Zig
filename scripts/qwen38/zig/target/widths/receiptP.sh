#!/usr/bin/env bash
# receiptP.sh - prompt speed of the widths step on images wm (main 2ba55ec7d3) and wb (main plus the widths patch):
# M1 B1 B2 M2, one fresh boot an arm with --prompt-cache-gib 0, each: ttft.py's cold 2k/8k/32k/64k prompts (3 salted
# reps, thinking off) and tools/bench_cache.py --require-cold (its own prompt). NVFP4, bf16 KV, 131,072 window,
# --parallel 4, as receiptW.sh. Waits for nothing; GPU lock held; production restored on every exit.
set -u
SELF=$(readlink -f "$0")
if [ "${RP_LOCKED:-}" != 1 ]; then
  flock -o -w 43200 ~/work/gpu.lock env RP_LOCKED=1 bash "$SELF" "$@"
  exit
fi
OUT=$HOME/work/widths/receiptP; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
UP=$HOME/work/widths/tools
URL=http://127.0.0.1:8080
MODEL=
log() { echo "$*" >> "$LOG"; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' '; }
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/prod.out" 2>&1
  log "RESTORE prod /health $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health) $(date -Is)"
  touch "$OUT/DONE"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
log "START $(date -Is)"
for im in wm wb; do
  docker image inspect tensorfold-qwen38:$im > /dev/null 2>&1 || { log "image $im missing"; exit 1; }
  log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"
done
arm() { # name image
  local d=$OUT/$1 img=$2
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart --prompt-cache-gib 0 </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $1 $(date -Is) boot rc $rc gpu $(gpu)"
  if [ "$rc" = 0 ]; then
    MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
    python3 ~/work/bench/ttft.py 8080 --sizes 2k,8k,32k,64k --thinking off --warm-add 0 --loads idle --reps 3 > "$d/ttft.out" 2>&1
    log "RC $1 ttft $? $(date -Is) gpu $(gpu)"
    python3 "$UP/bench_cache.py" $URL "$MODEL" --tokens 64 --repeats 2 --streams 1 --require-cold --output "$d/cache.json" > "$d/cache.out" 2>&1
    log "RC $1 cache $? $(date -Is) gpu $(gpu)"
  fi
  docker logs qwen38-flash-next-tf > "$d/server.log" 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
arm M1 wm
arm B1 wb
arm B2 wb
arm M2 wm
log "ARMS DONE $(date -Is)"
