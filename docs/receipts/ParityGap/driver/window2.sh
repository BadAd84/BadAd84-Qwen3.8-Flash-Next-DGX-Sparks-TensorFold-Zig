#!/usr/bin/env bash
# window2.sh - the parity-gap attribution window on spark6: six arms, one hold of ~/work/gpu.lock.
#
# WHAT IS MEASURED, and against what (the diff and the candidates are work/ParityGap/PLAN.md)
#   P   production as served (control), D the dev composition as served (control).
#   A1  D + TENSORFOLD_COPY_{MISS,RAMP,SHARED,RESYNC,RESYNC_PROMPT_ONLY}: production's copy policy under the
#       dev engine's own names (D's env carries the TF_FLASHNEXT_COPY_* spellings, which D's tree does not read).
#   A2  P + TF_FLASHNEXT_PROMPT_MM=0: the captured prompt-matmul path off (same bits by its own header).
#   A3  P + TF_FLASHNEXT_GRAPH_FAIL=1: every graph instantiate fails, rounds run eagerly (same result).
#   A4  D + LEARN=0: the persistent KV tier and its 6 GiB prompt-cache ask dropped.
#
#   Screen: C=1 and C=8, all six arms, P and D bracketing the arms at each level. Then score_arms.py --select
#   promotes at most two arms whose ratio against their own family control leaves 0.98-1.02 in either prompt
#   kind at either screen level; the promoted arms are booted again at C=2, C=4 and C=6 beside P and D.
#
#   Cells: golden 6/6 against the recorded stock reference, decode through tfm_decode_ids.py (3 passes, 512
#   greedy tokens, prose then code, a per-cell token hash), TTFT through ttft.py (cold 1k/8k/32k, thinking off
#   and on, 2 reps, idle) plus the warm 100k + 2k turn (2 reps, cached tokens recorded). Thermals at every
#   probe. The tier's store is cleared from a throwaway container before every D-family boot. No rerun pass:
#   repeat counts are the target's own and a screen verdict is re-measured by its own boot at 2/4/6.
#
# RESTORE: the EXIT trap stops whichever arm runs, starts production from its own launcher with the pinned
#   image, waits for /health 200, and runs the repo's kind-driven gate (gate/check-prod-env.py, 117 rows
#   compared, 0 problems) against a fresh docker inspect. The outer wrapper re-checks /health after the child
#   exits and restores again under the lock if it is not 200.
#
# MARKERS: LOCKED, PREFLIGHT, DRY, STOPPED, BOOT, ARMCHECK, PLAN, CELL-DONE, CELL-FAILED, BOOT-FAILED,
#   SELECT, CONFIRM, TABLES, RESTORE, RESTORED, RUN-DONE, WINDOW-DONE, EXIT-DONE.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/parity2
IN=$HOME/work/parity/in
OUT=$BOX/out
PROD_START=$HOME/qwen6-start-prod.sh
DEV_START=$HOME/qwen6-start.sh
P_RECIPE=$HOME/qwen-zig-prod
D_RECIPE=$HOME/qwen-zig
P_TAG=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
P_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
D_TAG=tensorfold-qwen38:r5dev40
D_ID=sha256:adc40fe3ea7b58b78f7957fcf37dbf3ac7e8d635172ccc42b4c5c85efeded74f
CACHE_DIR=$HOME/.cache/tensorfold-qwen38/4144696f21e3
CN=qwen38-flash-next-tf
PORT=8888
URL=http://127.0.0.1:$PORT
LEVEL_SCREEN=(1 8)
ORD1="P A1 A3 D A2 A4"
ORD8="D A2 A4 P A1 A3"
EXCLUDE=TF_REF,TF_REPO,TF_TAG,TF_RELEASE,TF_RELEASE_VERSION,TF_RELEASE_AARCH64_SHA256
START_EPOCH=""
EXITING=0
DEADLINE_MIN=${DEADLINE_MIN:-600}

if [ "${WIN2_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env WIN2_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "window2.sh exit $rc $(date -Is)" >> "$LOG"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health")
  if [ "$code" != 200 ]; then
    echo "OUTER-RESTORE needed after rc $rc (health $code); re-queuing for the lock" >> "$LOG"
    export LOG
    flock -o -w 900 "$HOME/work/gpu.lock" env OUTER_RESTORE=1 LOG="$LOG" bash -c '
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:8888/health)
      [ "$code" = 200 ] && { echo "OUTER-RESTORE skipped, health $code" >> "$LOG"; exit 0; }
      ( cd "$HOME/qwen-zig-prod" && ./stop.sh ) >> "$LOG" 2>&1 || true
      ( env -u IMAGE LOCK_HOLDER=0 "$HOME/qwen6-start-prod.sh" </dev/null ) >> "$LOG" 2>&1
      for i in $(seq 1 180); do code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:8888/health); [ "$code" = 200 ] && break; sleep 5; done
      img=$(docker inspect qwen38-flash-next-tf --format "{{.Config.Image}} {{.Image}}" 2>/dev/null || true)
      echo "OUTER-RESTORE /health $code image ${img:-absent} $(date -Is)" >> "$LOG"
    '
  fi
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
tag_of() { if [ "$1" = P ] || [ "$1" = A2 ] || [ "$1" = A3 ]; then echo "$P_TAG"; else echo "$D_TAG"; fi; }
id_of() { if [ "$1" = P ] || [ "$1" = A2 ] || [ "$1" = A3 ]; then echo "$P_ID"; else echo "$D_ID"; fi; }
recipe_of() { if [ "$1" = P ] || [ "$1" = A2 ] || [ "$1" = A3 ]; then echo "$P_RECIPE"; else echo "$D_RECIPE"; fi; }

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
  local arm=$1 C=$2 d=$3 ok=0 msg="" n
  case $arm in
    P) grep -qx 'TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; } ;;
    D) grep -qx 'TENSORFOLD_CUDA_KERNELS=native' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; } ;;
    A1)
      for n in TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_SHARED=1 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1; do
        grep -qx "$n" "$d/env.txt" || { ok=1; msg="$msg missing-$n"; }
      done
      grep -q 'copy policy: miss keep, ramp jump, shared rounds ramp prompt copies, resync prompt copies' "$d/server.log" \
        || { ok=1; msg="$msg bootline-copy"; }
      ;;
    A2)
      grep -qx 'TF_FLASHNEXT_PROMPT_MM=0' "$d/env.txt" || { ok=1; msg="$msg env-promptmm"; }
      grep -q 'matmul K slices split with _reduce' "$d/server.log" || { ok=1; msg="$msg bootline-promptmm"; }
      ;;
    A3)
      grep -qx 'TF_FLASHNEXT_GRAPH_FAIL=1' "$d/env.txt" || { ok=1; msg="$msg env-graphfail"; }
      grep -q 'injected failure' "$d/server.log" || { ok=1; msg="$msg bootline-graphfail"; }
      ;;
    A4)
      if grep -q 'prompt-cache-gib' "$d/cmd.json" 2>/dev/null; then ok=1; msg="$msg argv-tier-present"; fi
      if grep -q 'conversation states on disk' "$d/server.log" 2>/dev/null; then ok=1; msg="$msg log-tier-present"; fi
      grep -qx 'TENSORFOLD_CUDA_KERNELS=native' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; }
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
  "$BOX/boot_env2.sh" "$arm" "$C" 0 > "$d/boot.log" 2>&1 || rc=$?
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
  local arm=$1 C=$2 d=$3 img
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  curl -s --max-time 10 "$URL/health" > "$d/health.json" 2>/dev/null || true
  docker logs "$CN" > "$d/server.log" 2>&1 || true
  {
    grep -a -m1 -o '[0-9]* streams at once,.*' "$d/server.log"
    grep -a -m1 -o 'sequence memory: .*' "$d/server.log"
    grep -a -m1 -o 'prompt cache: .*' "$d/server.log"
    grep -a -m1 -o 'KV page groups: .*' "$d/server.log"
    grep -a -m1 -o 'prompt path: .*' "$d/server.log"
    grep -a -m1 -o 'copy policy: .*' "$d/server.log"
    grep -a -m1 -o 'graphs: .*' "$d/server.log"
    grep -a -m1 -o 'graph warm-up: .*' "$d/server.log"
    grep -a -m1 -o 'conversation states on disk.*' "$d/server.log"
    grep -a -m1 -o 'drafts: .*' "$d/server.log"
    grep -a -m1 -o 'draft head: .*' "$d/server.log"
    grep -a -m1 -o 'int4 kernels: .*' "$d/server.log"
    grep -a -m1 -o 'vision: .*' "$d/server.log"
    grep -a -m1 -o 'loaded in [0-9.]*s' "$d/server.log"
    grep -a -m1 -o '"max_batch_size": [0-9]*' "$d/health.json"
    grep -a -m1 -o '"context": [0-9]*' "$d/health.json"
  } > "$d/plan.txt" 2>/dev/null
  img=$(cat "$d/image-id.txt" 2>/dev/null)
  case "$img" in
    *"$(tag_of "$arm") $(id_of "$arm")"*) log "IDENTITY $arm c$C OK $img" ;;
    *) log "IDENTITY $arm c$C WRONG ${img:-absent} expected $(tag_of "$arm") $(id_of "$arm")" ;;
  esac
  while IFS= read -r line; do [ -n "$line" ] && log "PLAN $arm c$C $line"; done < "$d/plan.txt"
  armcheck "$arm" "$C" "$d"
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
gold() { # dir
  python3 "$IN/qf_harness.py" golden "$1/zgold.json" > "$1/gold.txt" 2>&1
  python3 "$IN/zgold_cmp.py" "$IN/zgold-base-c1.json" "$1/zgold.json" >> "$1/gold.txt" 2>&1
}
dec() { # dir label C
  rm -f "$1/dec.jsonl"
  python3 "$IN/tfm_decode_ids.py" "$2" "$3" "$1/dec.jsonl" 3 > "$1/dec.log" 2>&1
}
ttftp() { # dir
  python3 "$IN/ttft.py" "$PORT" --host 127.0.0.1 --model Qwen3.8-Flash-Next --sizes 1k,8k,32k \
    --thinking off,on --warm-base 100k --warm-add 2k --loads idle --reps 2 > "$1/ttft.out" 2>&1
}

shot_arm() { # arm C runno
  local arm=$1 C=$2 run=$3 d=$OUT/$1/c$2/run$3 rc=0
  mkdir -p "$d"
  if ! boot_arm "$arm" "$C" "$d"; then
    log "CELL-FAILED $arm c$C boot"
    stop_serve "$(recipe_of "$arm")"
    return 1
  fi
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
shoot() { # arm C runno
  local arm=$1 C=$2 run=$3
  case "$arm" in D|A1|A4) clear_dstore ;; esac
  shot_arm "$arm" "$C" "$run"
}

restore_production() {
  local img code erc
  log "RESTORE start $(date -Is)"
  img=$(docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null || true)
  code=$(healthcode)
  case "$img" in
    *"$P_TAG $P_ID"*)
      log "RESTORE already in place health $code image $img"
      [ "$code" = 200 ] || wait_health || log "RESTORE health wait timed out (image already the pinned one)"
      ;;
    *)
      stop_serve "$D_RECIPE"
      stop_serve "$P_RECIPE"
      ( env -u IMAGE LOCK_HOLDER=0 "$PROD_START" ) >> "$LOG" 2>&1
      wait_health || log "RESTORE health wait timed out"
      ;;
  esac
  mkdir -p "$OUT/restored"
  docker inspect "$CN" > "$OUT/restored/prod-inspect.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/restored/image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$OUT/restored/health.json" 2>/dev/null || true
  python3 "$BOX/gate/check-prod-env.py" --inspect "$OUT/restored/prod-inspect.json" \
    > "$OUT/restored/envcheck.txt" 2>&1
  erc=$?
  log "RESTORED health $(healthcode) image $(cat "$OUT/restored/image.txt" 2>/dev/null) envcheck rc $erc :: $(tail -1 "$OUT/restored/envcheck.txt" 2>/dev/null)"
}
final_exit() {
  [ "$EXITING" = 1 ] && return 0
  EXITING=1
  restore_production
  log "EXIT-DONE $(date -Is) health $(healthcode) image $(docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null)"
}
trap final_exit EXIT
trap 'exit 130' INT TERM HUP

# ---------------- the window ----------------
log "START $(date -Is) OUT $OUT driver $(sha256sum "$SELF" | cut -d' ' -f1)"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader); RAM $(free -g | awk '/^Mem:/{print $2}') GiB"
log "LAUNCHERS prod $(sha256sum "$PROD_START" 2>/dev/null | cut -c1-16) dev $(sha256sum "$DEV_START" 2>/dev/null | cut -c1-16); recipes prod $(sha256sum "$P_RECIPE/start.sh" 2>/dev/null | cut -c1-16) dev $(sha256sum "$D_RECIPE/start.sh" 2>/dev/null | cut -c1-16)"
log "PAYLOAD $(cd "$IN" && sha256sum *.py *.sh dev.env prod.env doc_target.json zgold-base-c1.json 2>/dev/null | tr '\n' ' ')"
log "DRIVER $(sha256sum "$BOX/boot_env2.sh" "$BOX/score_arms.py" 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

mkdir -p "$OUT/phase0"
for arm in P D A1 A2 A3 A4; do
  docker image inspect "$(tag_of "$arm")" -f '{{.Id}}' > "$OUT/phase0/img-$arm.txt" 2>&1 || true
  log "PREFLIGHT image $arm $(cat "$OUT/phase0/img-$arm.txt") expected $(id_of "$arm")"
  "$BOX/boot_env2.sh" "$arm" 1 1 > "$OUT/phase0/dry-$arm.txt" 2>&1 || log "DRY-FAILED $arm"
  case $arm in
    A1) grep -q 'TENSORFOLD_COPY_MISS=keep' "$OUT/phase0/dry-$arm.txt" && log "DRY $arm carries TENSORFOLD_COPY_MISS=keep" || log "DRY $arm MISSING the copy names";;
    A2) grep -q 'TF_FLASHNEXT_PROMPT_MM=0' "$OUT/phase0/dry-$arm.txt" && log "DRY $arm carries TF_FLASHNEXT_PROMPT_MM=0" || log "DRY $arm MISSING PROMPT_MM=0";;
    A3) grep -q 'TF_FLASHNEXT_GRAPH_FAIL=1' "$OUT/phase0/dry-$arm.txt" && log "DRY $arm carries TF_FLASHNEXT_GRAPH_FAIL=1" || log "DRY $arm MISSING GRAPH_FAIL=1";;
    A4) if grep -q 'prompt-cache-gib' "$OUT/phase0/dry-$arm.txt"; then log "DRY $arm STILL has the tier argv"; else log "DRY $arm has no tier argv"; fi;;
  esac
done
curl -s --max-time 10 "$URL/health" > "$OUT/phase0/live-health.json" 2>/dev/null || true
docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/phase0/live-image.txt" 2>/dev/null || true
docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$OUT/phase0/live-cmd.json" 2>/dev/null || true
docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort > "$OUT/phase0/live-env.txt" || true
log "PREFLIGHT live $(cat "$OUT/phase0/live-image.txt" 2>/dev/null) health $(healthcode) env_names $(wc -l < "$OUT/phase0/live-env.txt") gpu $(gpu) mem_avail $(memavail) disk $(diskfree)"

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

python3 "$BOX/score_arms.py" --root "$OUT" --select > "$OUT/select.txt" 2>&1
log "SELECT $(grep '^PROMOTE ' "$OUT/select.txt" | awk '{print $2}' | tr '\n' ' ')"
while IFS= read -r line; do log "SELECT-LINE $line"; done < "$OUT/select.txt"
PROMOTE=$(grep '^PROMOTE ' "$OUT/select.txt" | awk '{print $2}' | head -2 | tr '\n' ' ')
PROMOTE=${PROMOTE% }
if [ -n "${PROMOTE:-}" ]; then
  log "CONFIRM arms[$PROMOTE] at 2 4 6"
  for C in 2 4 6; do
    case $C in
      4) ORDER="D P $PROMOTE" ;;
      *) ORDER="P D $PROMOTE" ;;
    esac
    for arm in $ORDER; do
      [ "$(elapsed_min)" -ge "$DEADLINE_MIN" ] && { log "TIME-CAP before $arm c$C"; break 2; }
      shoot "$arm" "$C" 1
    done
  done
else
  log "CONFIRM-NONE no arm left the 0.98-1.02 band against its family control at the screen levels"
fi

python3 "$BOX/score_arms.py" --root "$OUT" --final > "$OUT/score.md" 2>&1
log "TABLES $(wc -l < "$OUT/score.md") lines in $OUT/score.md"
cp "$SELF" "$OUT/driver.sh" 2>/dev/null || true
cp "$BOX/boot_env2.sh" "$BOX/score_arms.py" "$OUT/" 2>/dev/null || true
log "RUN-DONE $(date -Is) elapsed $(elapsed_min) min"
log "WINDOW-DONE $(date -Is) cells $(find "$OUT" -name meta.txt | wc -l) score $OUT/score.md"
