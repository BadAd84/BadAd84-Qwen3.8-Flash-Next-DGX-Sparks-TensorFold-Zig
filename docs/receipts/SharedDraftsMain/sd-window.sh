#!/usr/bin/env bash
# sd-window.sh - task #4803: a clean upstream-main image, TF_FLASHNEXT_SHARED_DRAFTS=0 against =1, fresh
# servers alternating at 1, 2, 4 and 8 client streams, plus the cached two-stream control. One hold of
# ~/work/gpu.lock on spark6; production stopped inside the lock and restored by the EXIT trap.
#
# IMAGE   tensorfold-qwen38:main-9a38b1f7b, built from a git archive of ashhart/TensorFold
#         9a38b1f7b33863507cdea47e88207d8b3bea3f22 with no OTS patches (build log out/phase0/build.log).
# CKPT    nvidia/Qwen3.8-Flash-Next-FP4-Local at b9ce18a6887e18c089fdea8509a33e63429a3300, the ModelOpt
#         checkpoint main's own docs serve on one GB10 (docs/recipes/flash-next-cuda.md:236-241).
# ARMS    arm 0: TF_FLASHNEXT_SHARED_DRAFTS=0; arm 1: =1. Same launcher, checkpoint, flags, client, prompts.
# CELLS   C=1,2,4,8 x 3 cold passes; each boot also carries the idle TTFT cases; the cached two-stream control
#         is its own pair of boots. Order alternates which arm boots first: C1 0,1 C2 1,0 C4 0,1 C8 1,0 cached 1,0.
# SCORE   out/tables.md + out/score.json; a level whose decode passes span >5% is re-booted once for both arms.
# RESTORE /health 200, pinned production image id, check-prod-env.py --inspect (rows compared, 0 problems).
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/SharedDraftsMain
IN=$BOX/in
OUT=$BOX/out
IMG=tensorfold-qwen38:main-9a38b1f7b
CN=sd-main-tf
PROD_CN=qwen38-flash-next-tf
PROD_RECIPE=$HOME/qwen-zig-prod
PROD_START=$HOME/qwen6-start-prod.sh
P_TAG=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
P_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
URL=http://127.0.0.1:8888
LEVELS=(1 2 4 8)
declare -A ORD1=([1]="0 1" [2]="1 0" [4]="0 1" [8]="1 0")
declare -A ORD2=([1]="1 0" [2]="0 1" [4]="1 0" [8]="0 1")
START_EPOCH=""
EXITING=0

if [ "${SD_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env SD_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "sd-window.sh exit $rc $(date -Is)" >> "$LOG"
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health")
  if [ "$code" != 200 ]; then
    echo "OUTER-RESTORE needed after rc $rc (health $code); re-queuing for the lock" >> "$LOG"
    export LOG
    flock -o -w 900 "$HOME/work/gpu.lock" env OUTER_RESTORE=1 LOG="$LOG" bash -c '
      code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://127.0.0.1:8888/health)
      [ "$code" = 200 ] && { echo "OUTER-RESTORE skipped, health $code" >> "$LOG"; exit 0; }
      docker rm -f sd-main-tf >/dev/null 2>&1 || true
      ( cd "$HOME/qwen-zig-prod" && ./stop.sh ) >> "$LOG" 2>&1 || true
      docker rm -f qwen38-flash-next-tf >/dev/null 2>&1 || true
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
wait_health() { local i; for i in $(seq 1 240); do [ "$(healthcode)" = 200 ] && return 0; sleep 5; done; return 1; }
stop_mine() { docker rm -f "$CN" >/dev/null 2>&1 || true; }
stop_prod() { ( cd "$PROD_RECIPE" && ./stop.sh ) >> "$LOG" 2>&1 || true; docker rm -f "$PROD_CN" >/dev/null 2>&1 || true; }

capture() { # arm label dir phase
  local arm=$1 label=$2 d=$3 phase=$4
  docker inspect "$CN" > "$d/inspect-$phase.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id-$phase.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd-$phase.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env-$phase.txt" || true
  curl -s --max-time 10 "$URL/health" > "$d/health-$phase.json" 2>/dev/null || true
  curl -s --max-time 10 "$URL/v1/models" > "$d/models-$phase.json" 2>/dev/null || true
  curl -s --max-time 10 "$URL/metrics" > "$d/metrics-$phase.txt" 2>/dev/null || true
  docker logs "$CN" > "$d/server-log-$phase.txt" 2>&1 || true
  if [ "$phase" = boot ]; then
    {
      grep -a -m1 -o 'model directory:.*' "$d/server-log-boot.txt"
      grep -a -m1 -o '[0-9]* streams at once.*' "$d/server-log-boot.txt"
      grep -a -m1 -o 'prompt cache:.*' "$d/server-log-boot.txt"
      grep -a -m1 -o 'draft head:.*' "$d/server-log-boot.txt"
      grep -a -m1 -o -i 'NVFP4\|ModelOpt\|FP4\|quantiz[a-z]*' "$d/server-log-boot.txt" | head -3
      grep -a -m1 -o '"context": [0-9]*' "$d/health-boot.json"
      grep -a -m1 -o '"max_batch_size": [0-9]*' "$d/health-boot.json"
    } > "$d/plan.txt" 2>/dev/null || true
    echo "boot $(gpu) mem_avail $(memavail) disk $(diskfree)" >> "$d/gpu.txt"
    local got exp
    got=$(awk '{print $2}' "$d/image-id-boot.txt" 2>/dev/null)
    exp=$(docker image inspect "$IMG" --format '{{.Id}}' 2>/dev/null)
    if [ -n "$got" ] && [ "$got" = "$exp" ]; then
      log "IDENTITY-OK arm$arm $label $got"
    else
      log "IDENTITY-WRONG arm$arm $label ${got:-absent} expected ${exp:-absent}"
    fi
    log "ENV arm$arm $label $(tr '\n' ' ' < "$d/env-boot.txt")"
    while IFS= read -r line; do [ -n "$line" ] && log "PLAN arm$arm $label $line"; done < "$d/plan.txt"
  fi
}

run_cell() { # arm label mode level
  local arm=$1 label=$2 mode=$3 level=$4 d=$OUT/arm$arm/$2 rc=0
  rm -rf "$d"; mkdir -p "$d"
  if ! "$IN/sd-boot.sh" "$arm" > "$d/boot.log" 2>&1; then
    log "CELL-FAILED arm$arm $label boot :: $(tail -3 "$d/boot.log" | tr '\n' ' ')"
    stop_mine
    return 1
  fi
  log "BOOT arm$arm $label $(head -1 "$d/boot.log") gpu $(gpu) mem_avail $(memavail)"
  capture "$arm" "$label" "$d" boot
  python3 "$IN/sd_harness.py" --base "$URL" --model Qwen3.8-Flash-Next --out "$d" --mode "$mode" --level "$level" \
    > "$d/harness.log" 2>&1 || rc=$?
  while IFS= read -r line; do log "  $line"; done < "$d/harness.log"
  capture "$arm" "$label" "$d" end
  stop_mine
  log "CELL-DONE arm$arm $label mode $mode rc $rc elapsed $(elapsed_min) min"
  return $rc
}

phase0() {
  local d=$OUT/phase0
  mkdir -p "$d"
  cp "$IN/../build/build.log" "$d/build.log" 2>/dev/null || true
  docker image inspect "$IMG" > "$d/img.json" 2>&1 || true
  docker image inspect "$IMG" --format '{{.Id}} {{.Created}} {{.Size}}' > "$d/img-id.txt" 2>&1 || true
  docker run --rm --entrypoint /opt/tensorfold/native/bin/tensorfold-native "$IMG" --version > "$d/image-version.txt" 2>&1 || true
  docker run --rm --entrypoint sha256sum "$IMG" /opt/tensorfold/native/bin/tensorfold-native > "$d/binary-sha256.txt" 2>&1 || true
  docker run --rm --entrypoint sha256sum "$IMG" /opt/tensorfold/bin/tensorfold-native >> "$d/binary-sha256.txt" 2>&1 || true
  docker run --rm --network none --entrypoint sh "$IMG" -c \
    "grep -a -o -E '(TF|TENSORFOLD)_[A-Z0-9_]+' /opt/tensorfold/native/bin/tensorfold-native | sort -u" \
    > "$d/strings.txt" 2>&1 || true
  if grep -qx 'TF_FLASHNEXT_SHARED_DRAFTS' "$d/strings.txt"; then
    log "LEVER TF_FLASHNEXT_SHARED_DRAFTS present in the served binary's strings"
  else
    log "LEVER-MISSING TF_FLASHNEXT_SHARED_DRAFTS absent from the served binary's strings"
  fi
  local HF=$HOME/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local
  local REV=b9ce18a6887e18c089fdea8509a33e63429a3300
  cat "$HF/refs/main" > "$d/ckpt-ref.txt" 2>/dev/null || true
  ls -la "$HF/snapshots/$REV" > "$d/ckpt-ls.txt" 2>&1 || true
  du -sh "$HF" > "$d/ckpt-size.txt" 2>&1 || true
  sha256sum "$HF/snapshots/$REV/config.json" "$HF/snapshots/$REV/model.safetensors.index.json" \
    > "$d/ckpt-hashes.txt" 2>&1 || true
  python3 - "$HF/snapshots/$REV/model.safetensors.index.json" > "$d/ckpt-index.txt" 2>&1 <<'PY' || true
import json, sys
m = json.load(open(sys.argv[1]))
w = m.get("weight_map", {})
print("tensors", len(w), "files", len(set(w.values())))
print("model_type", json.load(open(sys.argv[1].replace("model.safetensors.index.json", "config.json"))).get("model_type"))
print("quantization_config", json.load(open(sys.argv[1].replace("model.safetensors.index.json", "config.json"))).get("quantization_config"))
PY
  log "CKPT ref $(cat "$d/ckpt-ref.txt" 2>/dev/null) :: $(tr '\n' ' ' < "$d/ckpt-index.txt")"
  log "CKPT hashes $(tr '\n' ' ' < "$d/ckpt-hashes.txt")"
  log "CKPT size $(cat "$d/ckpt-size.txt" 2>/dev/null)"

  # live production, the restore baseline (preflight runs before the lock stops it)
  docker inspect "$PROD_CN" > "$d/prod-inspect.json" 2>/dev/null || true
  docker inspect "$PROD_CN" --format '{{.Config.Image}} {{.Image}}' > "$d/prod-image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$d/prod-health.json" 2>/dev/null || true
  python3 "$IN/check-prod-env.py" --inspect "$d/prod-inspect.json" > "$d/prod-envcheck.txt" 2>&1 || true
  log "LIVE prod $(cat "$d/prod-image.txt" 2>/dev/null) health $(healthcode) envcheck :: $(tail -1 "$d/prod-envcheck.txt" 2>/dev/null)"
  log "PREFLIGHT image $(cat "$d/img-id.txt" 2>/dev/null) version $(cat "$d/image-version.txt" 2>/dev/null) binary $(cat "$d/binary-sha256.txt" 2>/dev/null | tr '\n' ' ')"
  log "PREFLIGHT strings $(wc -l < "$d/strings.txt") setting names; lock-holders $(pgrep -af '[f]lock .*gpu\.lock' | head -2 | tr '\n' ' ')"
}

smoke_once() {
  local d=$1 rc=0
  rm -rf "$d"; mkdir -p "$d"
  if ! "$IN/sd-boot.sh" 1 > "$d/boot.log" 2>&1; then
    log "SMOKE-FAILED boot :: $(tail -6 "$d/boot.log" | tr '\n' ' ')"
    stop_mine
    return 1
  fi
  capture 1 smoke "$d" boot
  python3 "$IN/sd_harness.py" --base "$URL" --model Qwen3.8-Flash-Next --out "$d" --mode smoke \
    > "$d/harness.log" 2>&1 || rc=$?
  grep -q '"complete": true' "$d/cell.json" 2>/dev/null || rc=1
  capture 1 smoke "$d" end
  stop_mine
  if [ "$rc" = 0 ]; then
    log "SMOKE-OK cache_gib ${CACHE_GIB:-3} $(tail -3 "$d/harness.log" | tr '\n' ' ')"
  else
    log "SMOKE-FAILED rc $rc cache_gib ${CACHE_GIB:-3} :: $(tail -6 "$d/harness.log" | tr '\n' ' ')"
  fi
  return $rc
}

smoke() {
  # One boot of the default arm before any measured cell: proves the loader admits this checkpoint with the
  # prompt cache and that the harness reads a complete reply. A failure ends the window (the trap restores).
  # Declared fallback: if the 3 GiB cache is refused, one retry at 1 GiB for BOTH arms (logged, and the flags
  # of every boot are captured in cmd-boot.json).
  smoke_once "$OUT/smoke" && return 0
  if [ "${CACHE_GIB:-3}" != 1 ]; then
    log "SMOKE-RETRY with a 1 GiB prompt cache after the failure above"
    export CACHE_GIB=1
    smoke_once "$OUT/smoke-1gib" && return 0
  fi
  return 1
}

restore_production() {
  local img code erc
  log "RESTORE start $(date -Is)"
  stop_mine
  img=$(docker inspect "$PROD_CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null || true)
  code=$(healthcode)
  case "$img" in
    *"$P_TAG $P_ID"*)
      log "RESTORE already in place health $code image $img"
      [ "$code" = 200 ] || wait_health || log "RESTORE health wait timed out (image already the pinned one)"
      ;;
    *)
      stop_prod
      ( env -u IMAGE LOCK_HOLDER=0 "$PROD_START" ) >> "$LOG" 2>&1
      wait_health || log "RESTORE health wait timed out"
      ;;
  esac
  mkdir -p "$OUT/restored"
  docker inspect "$PROD_CN" > "$OUT/restored/prod-inspect.json" 2>/dev/null || true
  docker inspect "$PROD_CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/restored/image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$OUT/restored/health.json" 2>/dev/null || true
  python3 "$IN/check-prod-env.py" --inspect "$OUT/restored/prod-inspect.json" \
    > "$OUT/restored/envcheck.txt" 2>&1
  erc=$?
  log "RESTORED health $(healthcode) image $(cat "$OUT/restored/image.txt" 2>/dev/null) envcheck rc $erc :: $(tail -1 "$OUT/restored/envcheck.txt" 2>/dev/null)"
}
final_exit() {
  [ "$EXITING" = 1 ] && return 0
  EXITING=1
  restore_production
  log "EXIT-DONE $(date -Is) health $(healthcode) image $(docker inspect "$PROD_CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null)"
}
trap final_exit EXIT
trap 'exit 130' INT TERM HUP

log "START $(date -Is) OUT $OUT driver $(sha256sum "$SELF" | cut -d' ' -f1)"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader); RAM $(free -g | awk '/^Mem:/{print $2}') GiB"
log "PAYLOAD $(cd "$IN" && sha256sum sd_harness.py sd-boot.sh check-prod-env.py prod.env register.env 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

phase0
log "GPU pre-stop $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

stop_prod
log "STOPPED production for the matrix $(date -Is) health $(healthcode) mem_avail $(memavail)"
sleep 5

smoke || { log "ABORT the matrix after a smoke failure; restoring production"; exit 1; }

for C in "${LEVELS[@]}"; do
  for arm in ${ORD1[$C]}; do run_cell "$arm" "c$C" decode "$C"; done
done
for arm in 1 0; do run_cell "$arm" cached cached 2; done
python3 "$IN/sd_score.py" --root "$OUT" > "$OUT/score1.txt" 2>&1 || true
log "SCORE1 $(grep -m1 '^SCORE-SUMMARY' "$OUT/score1.txt")"
grep '^RERUN' "$OUT/score1.txt" | awk '{print $3}' | sed 's/^c//' | sort -n | uniq > "$OUT/rerun1.levels" || true
log "RERUN levels[$(tr '\n' ' ' < "$OUT/rerun1.levels")]"
while read -r C; do
  [ -n "${C:-}" ] || continue
  for arm in ${ORD2[$C]}; do run_cell "$arm" "c$C-run2" decode "$C"; done
done < "$OUT/rerun1.levels"
python3 "$IN/sd_score.py" --root "$OUT" --final > "$OUT/score2.txt" 2>&1 || true
log "SCORE2 $(grep -m1 '^SCORE-SUMMARY' "$OUT/score2.txt")"
grep '^RERUN' "$OUT/score2.txt" | while read -r _ arm cc reason; do log "RERUN-OPEN $arm $cc $reason"; done

python3 "$IN/sd_tables.py" --root "$OUT" > "$OUT/tables.md" 2>&1 || true
log "TABLES $(wc -l < "$OUT/tables.md") lines in $OUT/tables.md"
final_exit
log "WINDOW-DONE $(date -Is) elapsed $(elapsed_min) min health $(healthcode) image $(docker inspect "$PROD_CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null)"
