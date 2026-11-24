#!/usr/bin/env bash
# window3.sh - the second confirm pass for the parity-gap window: A1 and A3 at C=2, C=4 and C=6.
#
# Why a second driver: the first window's promotion rule carried at most two arms, and it promoted A2 (the
# prefill win, 13.6 percent) and A4 (the tier loss at C=8, 8.3 percent). A3's C=8 screen read 1.023 prose,
# 1.039 code and 0.953 cold-32k against P, and A1's screen read 0.981/0.978 against D at C=8; both are
# outside the 0.98-1.02 band and neither got its 2/4/6 boots. This window gives them theirs, with P and D
# re-booted as controls at every level, so every arm of the campaign has all five levels.
#
# It runs under the same lock, after the first window releases it (flock queues it), stops the serve, and
# restores production from its own launcher in an EXIT trap with the repo's kind-driven gate, exactly as
# window2.sh does. Output: ~/work/parity2/out3, marker WINDOW3-DONE.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/parity2
IN=$HOME/work/parity/in
OUT=$BOX/out3
PROD_START=$HOME/qwen6-start-prod.sh
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
START_EPOCH=""
EXITING=0

if [ "${WIN3_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env WIN3_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "window3.sh exit $rc $(date -Is)" >> "$LOG"
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
  log "RESOURCES-TIMEOUT mem_avail $(memavail) disk $(diskfree); trying the boot anyway"
  return 0
}
clear_dstore() {
  docker run --rm -v "$CACHE_DIR":/cache --entrypoint sh "$D_TAG" -c \
    'printf "before kv=%s kvtier=%s\n" "$(du -sh /cache/kv 2>/dev/null | cut -f1)" "$(du -sh /cache/kvtier 2>/dev/null | cut -f1)"; rm -rf /cache/kv /cache/kvtier; echo cleared' \
    >> "$LOG" 2>&1 || log "CACHE-CLEAR failed"
}
armcheck() {
  local arm=$1 C=$2 d=$3 ok=0 msg="" n
  case $arm in
    P) grep -qx 'TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; } ;;
    D) grep -qx 'TENSORFOLD_CUDA_KERNELS=native' "$d/env.txt" || { ok=1; msg="$msg env-kernels"; } ;;
    A1)
      for n in TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_SHARED=1 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1; do
        grep -qx "$n" "$d/env.txt" || { ok=1; msg="$msg missing-$n"; }
      done
      grep -q 'copy policy: miss keep, ramp jump, shared rounds ramp prompt copies, resync prompt copies' "$d/server.log" || { ok=1; msg="$msg bootline-copy"; }
      ;;
    A3)
      grep -qx 'TF_FLASHNEXT_GRAPH_FAIL=1' "$d/env.txt" || { ok=1; msg="$msg env-graphfail"; }
      grep -q 'injected failure' "$d/server.log" || { ok=1; msg="$msg bootline-graphfail"; }
      ;;
  esac
  if [ "$ok" = 0 ]; then log "ARMCHECK $arm c$C OK"; else log "ARMCHECK $arm c$C FAIL$msg"; fi
  return 0
}
boot_arm() {
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
  [ "$rc" = 0 ] && [ "$code" = 200 ] || { log "BOOT-FAILED $arm c$C :: $(tail -3 "$d/boot.log" | tr '\n' ' ')"; return 1; }
  return 0
}
capture() {
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
    grep -a -m1 -o 'loaded in [0-9.]*s' "$d/server.log"
  } > "$d/plan.txt" 2>/dev/null
  img=$(cat "$d/image-id.txt" 2>/dev/null)
  case "$img" in
    *"$(tag_of "$arm") $(id_of "$arm")"*) log "IDENTITY $arm c$C OK $img" ;;
    *) log "IDENTITY $arm c$C WRONG ${img:-absent}" ;;
  esac
  while IFS= read -r line; do [ -n "$line" ] && log "PLAN $arm c$C $line"; done < "$d/plan.txt"
  armcheck "$arm" "$C" "$d"
}
probe() { local d=$1 name=$2 rc=0; shift 2; echo "$name gpu $(gpu)" >> "$d/gpu.txt"; "$@" > "$d/$name.out" 2>&1 || rc=$?; echo "$name gpu_after $(gpu)" >> "$d/gpu.txt"; log "PROBE ${d#"$OUT"/} $name rc $rc gpu $(gpu) mem_avail $(memavail)"; return $rc; }
gold() { python3 "$IN/qf_harness.py" golden "$1/zgold.json" > "$1/gold.txt" 2>&1; python3 "$IN/zgold_cmp.py" "$IN/zgold-base-c1.json" "$1/zgold.json" >> "$1/gold.txt" 2>&1; }
dec() { rm -f "$1/dec.jsonl"; python3 "$IN/tfm_decode_ids.py" "$2" "$3" "$1/dec.jsonl" 3 > "$1/dec.log" 2>&1; }
ttftp() { python3 "$IN/ttft.py" "$PORT" --host 127.0.0.1 --model Qwen3.8-Flash-Next --sizes 1k,8k,32k --thinking off,on --warm-base 100k --warm-add 2k --loads idle --reps 2 > "$1/ttft.out" 2>&1; }

shot_arm() {
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
shoot() { local arm=$1 C=$2 run=$3; case "$arm" in D|A1|A4) clear_dstore ;; esac; shot_arm "$arm" "$C" "$run"; }

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
      stop_serve "$D_RECIPE"; stop_serve "$P_RECIPE"
      ( env -u IMAGE LOCK_HOLDER=0 "$PROD_START" ) >> "$LOG" 2>&1
      wait_health || log "RESTORE health wait timed out"
      ;;
  esac
  mkdir -p "$OUT/restored"
  docker inspect "$CN" > "$OUT/restored/prod-inspect.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/restored/image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$OUT/restored/health.json" 2>/dev/null || true
  python3 "$BOX/gate/check-prod-env.py" --inspect "$OUT/restored/prod-inspect.json" > "$OUT/restored/envcheck.txt" 2>&1
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

log "START3 $(date -Is) OUT $OUT driver $(sha256sum "$SELF" | cut -d' ' -f1)"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); nvidia-smi $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader)"
log "PAYLOAD $(cd "$IN" && sha256sum *.py *.sh dev.env prod.env zgold-base-c1.json 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"
for arm in P D A1 A3; do docker image inspect "$(tag_of "$arm")" -f '{{.Id}}' > "$OUT/phase0-$arm.txt" 2>&1 || true; log "PREFLIGHT image $arm $(cat "$OUT/phase0-$arm.txt") expected $(id_of "$arm")"; done
stop_serve "$P_RECIPE"
log "STOPPED production for the confirm3 matrix $(date -Is) health $(healthcode) mem_avail $(memavail)"

for C in 2 4 6; do
  case $C in
    4) ORDER="D P A1 A3" ;;
    *) ORDER="P D A3 A1" ;;
  esac
  for arm in $ORDER; do shoot "$arm" "$C" 1; done
done
python3 "$BOX/score_arms.py" --root "$OUT" --final > "$OUT/score.md" 2>&1
python3 "$BOX/hash_cmp.py" --root "$OUT" > "$OUT/hashes.md" 2>&1
log "TABLES $(wc -l < "$OUT/score.md") lines in $OUT/score.md"
cp "$SELF" "$OUT/driver3.sh" 2>/dev/null || true
log "RUN3-DONE $(date -Is) elapsed $(elapsed_min) min"
log "WINDOW3-DONE $(date -Is) cells $(find "$OUT" -name meta.txt | wc -l) score $OUT/score.md"
