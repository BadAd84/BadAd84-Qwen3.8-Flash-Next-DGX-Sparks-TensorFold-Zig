#!/usr/bin/env bash
# window.sh - the 0041 prompt-tile window on spark6: three arms, one hold of ~/work/gpu.lock.
#
# WHAT IS MEASURED, and against what (the mechanism and the expectation are docs/receipts/PrefillKernelPort/):
#   F0  the dev composition as served (control): the engine's 128-column prompt tile.
#   F1  F0 + TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=8: the captured prompt matmul's geometry.
#   F2  F0 + TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=0: the column block alone.
#
#   Screen: C=1 and C=8, F0 and F1 bracketing F2 at each level. Then a confirm pass at C=2, C=4 and C=6 with
#   F0, F1 and F2 together, so the cold-prefill effect is read at every concurrency the dev env serves. All
#   three arms are the same engine, image and recipe, so a decode difference between them is not an isolation
#   and is reported as such.
#
#   Cells: golden 6/6 against the recorded stock reference, decode through tfm_decode_ids.py (3 passes, 512
#   greedy tokens, prose then code, a per-cell token hash), TTFT through ttft.py (cold 1k/8k/32k, thinking off
#   and on, 2 reps, idle) plus the warm 100k + 2k turn (2 reps). Thermals at every probe. The tier's store is
#   cleared from a throwaway container before every boot. No rerun pass: repeat counts are the target's own.
#
# RESTORE: the EXIT trap stops whichever arm runs, starts production from its own launcher with the pinned
#   image, waits for /health 200, and runs the repo's kind-driven gate (gate/check-prod-env.py) against a fresh
#   docker inspect. The outer wrapper re-checks /health after the child exits and restores again under the lock
#   if it is not 200.
#
# MARKERS: LOCKED, PREFLIGHT, DRY, STOPPED, BOOT, ARMCHECK, PROBE, CELL-DONE, CELL-FAILED, BOOT-FAILED,
#   TABLES, RESTORE, RESTORED, RUN-DONE, WINDOW-DONE, EXIT-DONE.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/pks
IN=$HOME/work/parity/in
OUT=$BOX/out
PROD_START=$HOME/qwen6-start-prod.sh
DEV_START=$HOME/qwen6-start.sh
P_RECIPE=$HOME/qwen-zig-prod
D_RECIPE=$HOME/qwen-zig
P_TAG=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
P_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
D_TAG=tensorfold-qwen38:ks41n
D_ID=sha256:27b7f3b70d9cb25a4301a0c4ae7f812eb102893c12336030c63290b4a4215e55
CACHE_DIR=$HOME/.cache/tensorfold-qwen38/4144696f21e3
CN=qwen38-flash-next-tf
PORT=8888
URL=http://127.0.0.1:$PORT
ORD1="F0 F1 F2"
ORD8="F2 F1 F0"
ORDER246="F0 F1 F2"
START_EPOCH=""
EXITING=0
DEADLINE_MIN=${DEADLINE_MIN:-600}

if [ "${PKS_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env PKS_LOCKED=1 LOG="$LOG" bash "$SELF"
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
diskfree() { df -Pk /var/lib/docker | awk 'NR==2{print int($4/1048576)}'; }
elapsed_min() { echo $(( ( $(date +%s) - START_EPOCH ) / 60 )); }
healthcode() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health"; }
wait_health() { local i; for i in $(seq 1 360); do [ "$(healthcode)" = 200 ] && return 0; sleep 5; done; return 1; }
tag_of() { echo "$D_TAG"; }
id_of() { echo "$D_ID"; }
recipe_of() { echo "$D_RECIPE"; }

stop_serve() {
  local recipe=$1 i
  ( cd "$recipe" && ./stop.sh ) >> "$LOG" 2>&1 || true
  for i in $(seq 1 90); do
    [ "$(docker inspect -f '{{.State.Running}}' "$CN" 2>/dev/null)" != true ] && return 0
    sleep 2
  done
  docker stop "$CN" >> "$LOG" 2>&1 || true
  return 0
}
wait_resources() {
  local i
  for i in $(seq 1 90); do
    [ "$(memavail)" -ge 92 ] && [ "$(diskfree)" -ge 25 ] && return 0
    sleep 10
  done
  log "RESOURCES-TIMEOUT mem_avail $(memavail) disk $(diskfree); trying the boot anyway (its own guard decides)"
  return 0
}
clear_dstore() {
  docker run --rm -v "$CACHE_DIR":/cache --entrypoint sh "$D_TAG" -c \
    'printf "before kv=%s kvtier=%s\n" "$(du -sh /cache/kv 2>/dev/null | cut -f1)" "$(du -sh /cache/kvtier 2>/dev/null | cut -f1)"; rm -rf /cache/kv /cache/kvtier; echo cleared' \
    >> "$LOG" 2>&1 || log "CACHE-CLEAR failed"
}

armcheck() { # arm C dir - the lever is proved from the boot's own env, argv and log
  local arm=$1 C=$2 d=$3 ok=0 msg=""
  case $arm in
    F0)
      grep -qx 'TENSORFOLD_CUDA_KERNELS=native' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; }
      if grep -q 'prompt matmuls: the fused K-slice tile' "$d/server.log"; then ok=1; msg="$msg bootline-ks-present"; fi
      ;;
    F1)
      grep -qx 'TF_FLASHNEXT_PROMPT_KS_N=64' "$d/env.txt" || { ok=1; msg="$msg env-ksn"; }
      grep -qx 'TF_FLASHNEXT_PROMPT_KS_GROUP=8' "$d/env.txt" || { ok=1; msg="$msg env-ksgroup"; }
      grep -q 'prompt matmuls: the fused K-slice tile on 64-column blocks, 8 row tiles a band' "$d/server.log" \
        || { ok=1; msg="$msg bootline-ks"; }
      ;;
    F2)
      grep -qx 'TF_FLASHNEXT_PROMPT_KS_N=64' "$d/env.txt" || { ok=1; msg="$msg env-ksn"; }
      grep -q 'prompt matmuls: the fused K-slice tile on 64-column blocks, 0 row tiles a band' "$d/server.log" \
        || { ok=1; msg="$msg bootline-ks-group0"; }
      ;;
  esac
  if [ "$ok" = 0 ]; then log "ARMCHECK $arm c$C OK"; else log "ARMCHECK $arm c$C FAIL$msg"; fi
  return 0
}

boot_arm() { # arm C dir
  local arm=$1 C=$2 d=$3 rc=0 t0 t1 code
  mkdir -p "$d"
  wait_resources || { log "RESOURCES-LOW $arm c$C mem_avail $(memavail) disk $(diskfree)"; return 1; }
  echo "boot_start $(gpu)" > "$d/gpu.txt"
  t0=$(date +%s.%N)
  "$BOX/boot_env.sh" "$arm" "$C" 0 > "$d/boot.log" 2>&1 || rc=$?
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN{printf "boot_s %.1f\n", b-a}' > "$d/boot_time.txt"
  echo "boot_rc $rc" >> "$d/boot_time.txt"
  code=$(healthcode)
  log "BOOT $arm c$C rc $rc health $code $(tr '\n' ' ' < "$d/boot_time.txt") gpu $(gpu) mem_avail $(memavail) disk $(diskfree)"
  [ "$rc" = 0 ] && [ "$code" = 200 ] || {
    log "BOOT-FAILED $arm c$C :: $(tail -3 "$d/boot.log" | tr '\n' ' ')"
    return 1
  }
  return 0
}

capture() { # arm C dir
  local arm=$1 C=$2 d=$3
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  curl -s --max-time 10 "$URL/health" > "$d/health.json" 2>/dev/null || true
  docker logs "$CN" > "$d/server.log" 2>&1 || true
  n=$(nvidia-smi --query-gpu=multiprocessor_count --format=csv,noheader 2>/dev/null || echo "")
  echo "sm_count ${n:-unknown}" > "$d/sm.txt"
  grep -a -m1 -o '[0-9]* streams at once,.*' "$d/server.log" >> "$d/sm.txt" || true
}

probe() { # dir name command...
  local d=$1 name=$2 rc=0
  shift 2
  echo "$name gpu $(gpu)" >> "$d/gpu.txt"
  "$@" > "$d/$name.out" 2>&1 || rc=$?
  echo "$name gpu_after $(gpu)" >> "$d/gpu.txt"
  log "PROBE ${d#"$OUT"/} $name rc $rc gpu $(gpu) mem_avail $(memavail)"
  return $rc
}
gold() { python3 "$IN/qf_harness.py" golden "$1/zgold.json" > "$1/gold.txt" 2>&1; python3 "$IN/zgold_cmp.py" "$IN/zgold-base-c1.json" "$1/zgold.json" >> "$1/gold.txt" 2>&1; }
dec() { rm -f "$1/dec.jsonl"; python3 "$IN/tfm_decode_ids.py" "$2" "$3" "$1/dec.jsonl" 3 > "$1/dec.log" 2>&1; }
ttftp() {
  python3 "$IN/ttft.py" "$PORT" --host 127.0.0.1 --model Qwen3.8-Flash-Next --sizes 1k,8k,32k \
    --thinking off,on --warm-base 100k --warm-add 2k --loads idle --reps 2 > "$1/ttft.out" 2>&1
}

shot_arm() { # arm C runno
  local arm=$1 C=$2 run=$3 d=$OUT/$1/c$2/run$3 rc=0
  mkdir -p "$d"
  if ! boot_arm "$arm" "$C" "$d"; then log "CELL-FAILED $arm c$C boot"; stop_serve "$(recipe_of "$arm")"; return 1; fi
  capture "$arm" "$C" "$d"
  probe "$d" gold gold "$d" || rc=$?
  probe "$d" dec dec "$d" "$arm-c$C" "$C" || rc=$?
  probe "$d" ttft ttftp "$d" || rc=$?
  armcheck "$arm" "$C" "$d"
  python3 "$IN/meta.py" "$d" "$arm" "$C" >/dev/null 2>&1
  stop_serve "$(recipe_of "$arm")"
  log "CELL-DONE $arm c$C run$run rc $rc elapsed $(elapsed_min) min"
  return $rc
}
shoot() { clear_dstore; shot_arm "$@"; }

final_exit() {
  [ "$EXITING" = 1 ] && return 0
  EXITING=1
  stop_serve "$D_RECIPE"
  log "EXIT-DONE $(date -Is) health $(healthcode)"
}
trap final_exit EXIT
trap 'exit 130' INT TERM HUP

# ---------------- the window ----------------
log "START $(date -Is) OUT $OUT driver $(sha256sum "$SELF" | cut -d' ' -f1)"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader); RAM $(free -g | awk '/^Mem:/{print $2}') GiB"
log "LAUNCHERS prod $(sha256sum "$PROD_START" 2>/dev/null | cut -c1-16) dev $(sha256sum "$DEV_START" 2>/dev/null | cut -c1-16)"
log "DRIVER $(sha256sum "$BOX/boot_env.sh" "$BOX/score_pks.py" 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

mkdir -p "$OUT/phase0"
for arm in F0 F1 F2; do
  docker image inspect "$(tag_of "$arm")" -f '{{.Id}}' > "$OUT/phase0/img-$arm.txt" 2>&1 || true
  log "PREFLIGHT image $arm $(cat "$OUT/phase0/img-$arm.txt") expected $(id_of "$arm")"
  "$BOX/boot_env.sh" "$arm" 1 1 > "$OUT/phase0/dry-$arm.txt" 2>&1 || log "DRY-FAILED $arm"
  case $arm in
    F0) if grep -q 'TF_FLASHNEXT_PROMPT_KS_N' "$OUT/phase0/dry-$arm.txt"; then log "DRY $arm UNEXPECTED KS name"; else log "DRY $arm carries no KS name (the control)"; fi;;
    F1) grep -q 'TF_FLASHNEXT_PROMPT_KS_N=64' "$OUT/phase0/dry-$arm.txt" && grep -q 'TF_FLASHNEXT_PROMPT_KS_GROUP=8' "$OUT/phase0/dry-$arm.txt" && log "DRY $arm carries KS_N=64 KS_GROUP=8" || log "DRY $arm MISSING the KS names";;
    F2) grep -q 'TF_FLASHNEXT_PROMPT_KS_N=64' "$OUT/phase0/dry-$arm.txt" && log "DRY $arm carries KS_N=64 (group default)" || log "DRY $arm MISSING KS_N";;
  esac
done

stop_serve "$P_RECIPE"
log "STOPPED production for the matrix $(date -Is) health $(healthcode) mem_avail $(memavail)"

for arm in $ORD1; do
  [ "$(elapsed_min)" -ge "$DEADLINE_MIN" ] && { log "TIME-CAP before $arm c1"; break; }
  shoot "$arm" 1 1
done
for arm in $ORD8; do
  [ "$(elapsed_min)" -ge "$DEADLINE_MIN" ] && { log "TIME-CAP before $arm c8"; break; }
  shoot "$arm" 8 1
done

for C in 2 4 6; do
  for arm in $ORDER246; do
    [ "$(elapsed_min)" -ge "$DEADLINE_MIN" ] && { log "TIME-CAP before $arm c$C"; break 2; }
    shoot "$arm" "$C" 1
  done
done

python3 "$BOX/score_pks.py" --root "$OUT" --final > "$OUT/score.md" 2>&1
log "TABLES $(wc -l < "$OUT/score.md") lines in $OUT/score.md"
cp "$SELF" "$OUT/driver.sh" 2>/dev/null || true
cp "$BOX/boot_env.sh" "$BOX/score_pks.py" "$OUT/" 2>/dev/null || true
log "RUN-DONE $(date -Is) elapsed $(elapsed_min) min"
log "WINDOW-DONE $(date -Is) cells $(find "$OUT" -name meta.txt | wc -l) score $OUT/score.md"
