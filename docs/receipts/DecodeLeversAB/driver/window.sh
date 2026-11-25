#!/usr/bin/env bash
# window.sh - 5-level (C=1,2,4,6,8) promotion A/B for TF_FLASHNEXT_DECODE_GRAPH=1 (G1) and
# TF_FLASHNEXT_ATTN_LANES=1 (A1) against control B0 on spark6 (ks41n, KV_DTYPE=bf16).
# Includes golden 6/6, 3-pass greedy decode with reply hashes, and TTFT (cold 1k/8k/32k + warm 100k+2k).
# No production restore on exit (owner 2026-11-25).
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/dlab
IN=$HOME/work/parity/in
OUT=$BOX/out
DEV_START=$HOME/qwen6-start.sh
D_RECIPE=$HOME/qwen-zig
D_TAG=tensorfold-qwen38:ks41n
D_ID=sha256:27b7f3b70d9cb25a4301a0c4ae7f812eb102893c12336030c63290b4a4215e55
CACHE_DIR=$HOME/.cache/tensorfold-qwen38/4144696f21e3
CN=qwen38-flash-next-tf
PORT=8888
URL=http://127.0.0.1:$PORT
EXITING=0

if [ "${DLAB_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env DLAB_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "window.sh exit $rc $(date -Is)" >> "$LOG"
  exit $rc
fi

LOG=${LOG:-$OUT/run.log}
START_EPOCH=$(date +%s)
mkdir -p "$OUT"
log() { echo "[$(date -Is)] $*" | tee -a "$LOG"; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw,memory.used --format=csv,noheader 2>/dev/null | tr -d ' ' | tr '\n' ';'; }
memavail() { awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo; }
elapsed_min() { echo $(( ( $(date +%s) - START_EPOCH ) / 60 )); }
healthcode() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health"; }

stop_serve() {
  ( cd "$D_RECIPE" && ./stop.sh ) >> "$LOG" 2>&1 || true
  for _ in $(seq 1 60); do
    [ "$(docker inspect -f '{{.State.Running}}' "$CN" 2>/dev/null)" != true ] && return 0
    sleep 2
  done
  docker stop "$CN" >> "$LOG" 2>&1 || true
}
clear_dstore() {
  docker run --rm -v "$CACHE_DIR":/cache --entrypoint sh "$D_TAG" -c \
    'rm -rf /cache/kv /cache/kvtier' >> "$LOG" 2>&1 || true
}

arm_override() {
  case "$1" in
    B0) echo "" ;;
    G1) echo "TF_FLASHNEXT_DECODE_GRAPH=1" ;;
    A1) echo "TF_FLASHNEXT_ATTN_LANES=1" ;;
  esac
}
arm_expect() {
  case "$1" in
    B0) echo "TF_FLASHNEXT_DECODE_GRAPH=0" ;;
    G1) echo "TF_FLASHNEXT_DECODE_GRAPH=1" ;;
    A1) echo "TF_FLASHNEXT_ATTN_LANES=1" ;;
  esac
}

boot_arm() {
  local arm=$1 C=$2 d=$3 ov rc=0 t0 t1 code
  ov=$(arm_override "$arm")
  mkdir -p "$d"
  t0=$(date +%s.%N)
  (
    set +u
    . "$IN/dev.env"
    set -u
    export LOCK_HOLDER=0 PARALLEL="$C" CONTEXT=262144 HOST=127.0.0.1 WARM_TURNS=0 IMAGE="$D_TAG"
    if [ -n "$ov" ]; then export "$ov"; fi
    exec "$DEV_START"
  ) > "$d/boot.log" 2>&1 || rc=$?
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN{printf "boot_s %.1f\n", b-a}' > "$d/boot_time.txt"
  code=$(healthcode)
  log "BOOT $arm c$C rc $rc health $code $(cat "$d/boot_time.txt") gpu $(gpu) mem_avail $(memavail)"
  [ "$rc" = 0 ] && [ "$code" = 200 ] || { log "BOOT-FAILED $arm c$C :: $(tail -3 "$d/boot.log" | tr '\n' ' ')"; return 1; }
  return 0
}

run_cell() {
  local arm=$1 C=$2 d=$OUT/$1/c$2/run1 rc=0 exp
  clear_dstore
  if ! boot_arm "$arm" "$C" "$d"; then stop_serve; log "CELL-FAILED $arm c$C"; return 1; fi
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  docker logs "$CN" > "$d/server.log" 2>&1 || true
  exp=$(arm_expect "$arm")
  if grep -qx "$exp" "$d/env.txt"; then log "ARMCHECK $arm c$C OK ($exp)"; else log "ARMCHECK $arm c$C FAIL (want $exp)"; fi
  python3 "$IN/qf_harness.py" golden "$d/zgold.json" > "$d/gold.txt" 2>&1 || rc=$?
  python3 "$IN/zgold_cmp.py" "$IN/zgold-base-c1.json" "$d/zgold.json" >> "$d/gold.txt" 2>&1 || rc=$?
  log "PROBE $arm/c$C gold rc $rc $(tail -1 "$d/gold.txt")"
  rm -f "$d/dec.jsonl"
  python3 "$IN/tfm_decode_ids.py" "$arm-c$C" "$C" "$d/dec.jsonl" 3 > "$d/dec.log" 2>&1 || rc=$?
  log "PROBE $arm/c$C dec rc $rc gpu $(gpu)"
  python3 "$IN/ttft.py" "$PORT" --host 127.0.0.1 --model Qwen3.8-Flash-Next --sizes 1k,8k,32k \
    --thinking off,on --warm-base 100k --warm-add 2k --loads idle --reps 2 > "$d/ttft.out" 2>&1 || rc=$?
  log "PROBE $arm/c$C ttft rc $rc gpu $(gpu)"
  stop_serve
  log "CELL-DONE $arm c$C rc $rc elapsed $(elapsed_min) min"
}

final_exit() {
  [ "$EXITING" = 1 ] && return 0
  EXITING=1
  stop_serve
  log "EXIT-DONE $(date -Is) health $(healthcode)"
}
trap final_exit EXIT
trap 'exit 130' INT TERM HUP

log "START $(date -Is) OUT $OUT"
log "IMAGE $(docker image inspect "$D_TAG" -f '{{.Id}}' 2>/dev/null) expected $D_ID"
stop_serve

for arm in B0 G1 A1; do run_cell "$arm" 1; done
for arm in A1 G1 B0; do run_cell "$arm" 8; done
for arm in B0 G1 A1; do run_cell "$arm" 2; done
for arm in A1 G1 B0; do run_cell "$arm" 4; done
for arm in B0 G1 A1; do run_cell "$arm" 6; done

python3 "$BOX/score.py" --root "$OUT" --final > "$OUT/score.md" 2>&1 || true
log "WINDOW-DONE $(date -Is) elapsed $(elapsed_min) min"
