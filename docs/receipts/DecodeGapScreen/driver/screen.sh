#!/usr/bin/env bash
# screen.sh - single-lever decode-gap screen on spark6 (tensorfold-qwen38:ks41n, KV_DTYPE=bf16).
#
# Arms (each differs from D0 by exactly one env setting, verified in container env.txt):
#   D0a  control (dev.env + qwen6-start.sh defaults)
#   D1   TF_FLASHNEXT_ATTN_LANES=1
#   D2   TF_FLASHNEXT_DECODE_GRAPH=1
#   D3   TF_FLASHNEXT_READOUT_FUSE=1
#   D4   TF_QMMF_HALF_BELOW=0
#   D5   TF_FLASHNEXT_SHARED_SIDE=0
#   D6   MTP_WEIGHTS=bf16 (vs mxfp8 default; clears r5 drafter A/B debt)
#   D0b  repeat control (thermal / spread bracket)
#
# Levels: C=8 first (where the 9.5% decode gap is largest), then C=1.
# No production restore on exit (owner 2026-11-25); stops arm container cleanly.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/dgs
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
ARMS="D0a D1 D2 D3 D4 D5 D6 D0b"
LEVELS=${LEVELS:-"8 1"}
EXITING=0

if [ "${DGS_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env DGS_LOCKED=1 LOG="$LOG" LEVELS="$LEVELS" bash "$SELF"
  rc=$?
  echo "screen.sh exit $rc $(date -Is)" >> "$LOG"
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
    D0a|D0b) echo "" ;;
    D1) echo "TF_FLASHNEXT_ATTN_LANES=1" ;;
    D2) echo "TF_FLASHNEXT_DECODE_GRAPH=1" ;;
    D3) echo "TF_FLASHNEXT_READOUT_FUSE=1" ;;
    D4) echo "TF_QMMF_HALF_BELOW=0" ;;
    D5) echo "TF_FLASHNEXT_SHARED_SIDE=0" ;;
    D6) echo "MTP_WEIGHTS=bf16" ;;
  esac
}
arm_expect() {
  case "$1" in
    D0a|D0b) echo "TF_FLASHNEXT_ATTN_LANES=0" ;;
    D1) echo "TF_FLASHNEXT_ATTN_LANES=1" ;;
    D2) echo "TF_FLASHNEXT_DECODE_GRAPH=1" ;;
    D3) echo "TF_FLASHNEXT_READOUT_FUSE=1" ;;
    D4) echo "TF_QMMF_HALF_BELOW=0" ;;
    D5) echo "TF_FLASHNEXT_SHARED_SIDE=0" ;;
    D6) echo "TF_FLASHNEXT_MTP_WEIGHTS=bf16" ;;
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
  local arm=$1 C=$2 d=$OUT/$1/c$2 rc=0 exp
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

log "START $(date -Is) OUT $OUT LEVELS='$LEVELS' ARMS='$ARMS'"
log "IMAGE $(docker image inspect "$D_TAG" -f '{{.Id}}' 2>/dev/null) expected $D_ID"
stop_serve

for C in $LEVELS; do
  for arm in $ARMS; do
    run_cell "$arm" "$C"
  done
done

python3 "$BOX/score.py" --root "$OUT" > "$OUT/score.md" 2>&1 || true
log "WINDOW-DONE $(date -Is) elapsed $(elapsed_min) min"
