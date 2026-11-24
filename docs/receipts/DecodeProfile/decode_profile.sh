#!/usr/bin/env bash
# decode_profile.sh - one GPU window on spark6 that profiles ONE decode round on each engine (P and D),
# same checkpoint, same prompt length, same draft settings, one stream.
#
# Per arm it does THREE independent captures:
#   1. the engine's own TF_FLASHNEXT_PROFILE=1 per-part GPU timeline (a decode round by named stage,
#      ms a round and percent) - the primary stage table, read from the serve's own log on graceful stop;
#   2. an nsys kernel-and-memory census of the decode phase under the same env (nsys captures on this
#      GB10 box only when the profiled process runs synchronously: NSYS_FOREGROUND=1);
#   3. a k-step decode trace on off-port 8899: one stream, greedy, identical prompt, a fixed step count,
#      stopped mid-decode so nsys flushes the decode window (CUPTI still records the kernels; only the
#      name table is best effort).
#
# PROFILE=1 forces eager rounds (graphs off while profiling, cuda_engine.zig:2125), so the per-part
# timeline is the eager composition on both arms and is read as a comparison of the same measurement.
#
# The recipe start.sh runs the serve in the foreground (FOREGROUND=1) when NSYS_FOREGROUND=1, which is
# what the GB10 box needs; the profile boot is therefore launched detached with nohup by this driver.
#
# Output: ~/work/prof/out, marker PROFILE-DONE. Production is restored from the EXIT trap with the
# repo's kind-driven gate. Usage: decode_profile.sh            (queues for the lock)
#                                  decode_profile.sh --locked   (internal)
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/prof
OUT=$BOX/out
IN=$HOME/work/parity/in
GATE=$HOME/work/parity2/gate
P_RECIPE=$HOME/qwen-zig-prod
D_RECIPE=$HOME/qwen-zig
P_TAG=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
P_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
D_TAG=tensorfold-qwen38:r5dev40
D_ID=sha256:adc40fe3ea7b58b78f7957fcf37dbf3ac7e8d635172ccc42b4c5c85efeded74f
CACHE_DIR=$HOME/.cache/tensorfold-qwen38/4144696f21e3
PROD_START=$HOME/qwen6-start-prod.sh
CN=qwen38-flash-next-tf
PROFCN=qwen38-prof
PORT=8888
APORT=8899
URL=http://127.0.0.1:$PORT
AURL=http://127.0.0.1:$APORT
STEPS=${STEPS:-64}
model_dir=/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd

if [ "${DP_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env DP_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "decode_profile.sh exit $rc $(date -Is)" >> "$LOG"
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
      echo "OUTER-RESTORE /health $code $(date -Is)" >> "$LOG"
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
achealthcode() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$AURL/health"; }
wait_health() { local i; for i in $(seq 1 360); do [ "$(healthcode)" = 200 ] && return 0; sleep 5; done; return 1; }
wait_ahealth() { local i; for i in $(seq 1 $(( ${1:-180} / 5 )) ); do [ "$(achealthcode)" = 200 ] && return 0; sleep 5; done; return 1; }
tag_of() { if [ "$1" = P ]; then echo "$P_TAG"; else echo "$D_TAG"; fi; }
id_of() { if [ "$1" = P ]; then echo "$P_ID"; else echo "$D_ID"; fi; }
recipe_of() { if [ "$1" = P ]; then echo "$P_RECIPE"; else echo "$D_RECIPE"; fi; }

stop_cn() { # container name, recipe
  local cn=$1 recipe=$2 i
  ( cd "$recipe" && ./stop.sh ) >> "$LOG" 2>&1 || true
  for i in $(seq 1 90); do
    [ "$(docker inspect -f '{{.State.Running}}' "$cn" 2>/dev/null)" != true ] && return 0
    sleep 2
  done
  docker stop "$cn" >> "$LOG" 2>&1 || true
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
    'rm -rf /cache/kv /cache/kvtier; echo cleared' >> "$LOG" 2>&1 || log "CACHE-CLEAR failed"
}

# ---- the arm environment, one place, mirrors boot_env2.sh + the env files of record --------------
# env_lines ARM -> the -e NAME=VALUE lines and the serve argv for that arm, one per line on stdout,
# prefixed "ENV " for -e args and "ARG " for serve arguments.
arm_env() {
  local arm=$1
  if [ "$arm" = P ]; then
    echo "ENV HF_HUB_OFFLINE=1"
    echo "ENV TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121"
    echo "ENV TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/tensorfold-mtp-fp8/azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/1464274120d36a4d8fcaa934552334a7d83ce0fd"
    grep -E '^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=' "$IN/prod.env" | sed 's/^/ENV /'
    echo "ENV TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121"
    echo "ENV TENSORFOLD_WARM_TURNS=0"
    echo "ENV TENSORFOLD_MEMORY_RESERVE_GIB=10"
    echo "ENV TENSORFOLD_IMAGE_TOKENS=16384"
    echo "ENV TENSORFOLD_MAX_IMAGES=50"
    echo "ENV TENSORFOLD_VIDEO_TOKENS=16384"
    echo "ENV TENSORFOLD_VISION_WORKSPACE_MIB=2048"
    echo "ENV TENSORFOLD_PROMPT_CACHE_WHOLE=1"
    echo "ENV TENSORFOLD_PROMPT_CACHE_WHOLE_MIN=1024"
    # serve arguments: production's launcher block
    echo "ARG --context 262144"
    echo "ARG --parallel 1"
    echo "ARG --max-tokens 32768"
    echo "ARG --temperature 0"
    echo "ARG --top-p 1"
    echo "ARG --top-k 0"
    echo "ARG --no-thinking"
    echo "ARG --kv-dtype fp8"
    echo "ARG --vision --vision-max-images 50 --vision-max-videos 2 --vision-image-tokens 16384"
    return 0
  fi
  # D family: dev.env is the environment of record; D adds the tier argv
  echo "ENV HF_HUB_OFFLINE=1"
  echo "ENV TENSORFOLD_CUDA_KERNELS=native"
  grep -E '^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=' "$IN/dev.env" | sed 's/^/ENV /'
  echo "ENV TENSORFOLD_MEMORY_RESERVE_GIB=9"
  echo "ENV TENSORFOLD_WARM_TURNS=0"
  echo "ENV TF_FLASHNEXT_MTP_WEIGHTS=mxfp8"
  echo "ENV CHECKPOINT=int4"
  echo "ARG --context 262144"
  echo "ARG --parallel 1"
  echo "ARG --max-tokens 32768"
  echo "ARG --temperature 0"
  echo "ARG --top-p 1"
  echo "ARG --top-k 0"
  echo "ARG --no-thinking"
  echo "ARG --kv-cache fp8"
  echo "ARG --prompt-cache-gib 6 --prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20"
}

# ---- capture -------------------------------------------------------------------------------------
capture() {
  local arm=$1 d=$2 cn=${3:-$CN} port=${4:-$PORT} img
  docker inspect "$cn" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id.txt" 2>/dev/null || true
  docker inspect "$cn" --format '{{json .Config.Cmd}}' > "$d/cmd.json" 2>/dev/null || true
  docker inspect "$cn" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  curl -s --max-time 10 "http://127.0.0.1:$port/health" > "$d/health.json" 2>/dev/null || true
  docker logs "$cn" > "$d/server.log" 2>&1 || true
  {
    grep -a -m1 -o '[0-9]* streams at once,.*' "$d/server.log"
    grep -a -m1 -o 'sequence memory: .*' "$d/server.log"
    grep -a -m1 -o 'fp8 KV cache, [0-9]* bytes a position a layer' "$d/server.log"
    grep -a -m1 -o 'KV page groups: .*' "$d/server.log"
    grep -a -m1 -o 'copy policy: .*' "$d/server.log"
    grep -a -m1 -o 'graphs: .*' "$d/server.log"
    grep -a -m1 -o 'loaded in [0-9.]*s' "$d/server.log"
  } > "$d/plan.txt" 2>/dev/null
  img=$(cat "$d/image-id.txt" 2>/dev/null)
  case "$img" in
    *"$(tag_of "$arm") $(id_of "$arm")"*) log "IDENTITY $arm OK $img" ;;
    *) log "IDENTITY $arm WRONG ${img:-absent}" ;;
  esac
  while IFS= read -r line; do [ -n "$line" ] && log "PLAN $arm $line"; done < "$d/plan.txt"
}

# ---- the decode trace: one stream, greedy, fixed steps, stopped mid-decode -----------------------
trace() {
  local d=$1 steps=$2 rc=0
  python3 "$BOX/trace_decode.py" "$APORT" --model Qwen3.8-Flash-Next --steps "$steps" \
      --prompt-file "$BOX/prompt1.txt" --out "$d/trace.jsonl" > "$d/trace.log" 2>&1 || rc=$?
  return $rc
}

# ---- boot one arm in the FOREGROUND of a detached child so nsys can capture ----------------------
# boot_profile ARM D OUTNS [TRACE_STEPS]
boot_profile() {
  local arm=$1 d=$2 nsout=$3 steps=$4 rc=0 t0 t1 code nsrel
  mkdir -p "$d"
  wait_resources || { log "RESOURCES-LOW $arm"; return 1; }
  echo "boot_start $(gpu)" > "$d/gpu.txt"
  local -a ENVS=() ARGS=()
  while read -r kind kv; do
    [ "$kind" = ENV ] && ENVS+=(-e "$kv")
    [ "$kind" = ARG ] && ARGS+=("$kv")
  done < <(arm_env "$arm")
  ENVS+=(-e "TF_FLASHNEXT_PROFILE=1" -e "TENSORFOLD_NO_UPDATE_CHECK=1" -e "TENSORFOLD_MEMORY_RESERVE_GIB=${TENSORFOLD_MEMORY_RESERVE_GIB:-9}")
  # nsys writes inside the container: the report path must be the CONTAINER path (/out is the host $OUT)
  nsrel="${nsout#"$OUT"/}"
  local NSYS=(/usr/local/cuda/bin/nsys profile -o "/out/$nsrel" -f true --trace=cuda,nvtx \
      --sample=none --cpuctxsw=none --cuda-graph-trace=node --kill=none)
  docker rm -f "$PROFCN" >/dev/null 2>&1 || true
  t0=$(date +%s.%N)
  docker run -d --name "$PROFCN" --gpus all --ipc=host --network host --cap-add SYS_ADMIN \
    --ulimit memlock=-1 --ulimit stack=67108864 "${ENVS[@]}" \
    -v "$HOME/.cache/huggingface":/root/.cache/huggingface:ro \
    -v "$CACHE_DIR":/cache \
    -v "$OUT":/out \
    "$(tag_of "$arm")" \
    "${NSYS[@]}" /usr/local/bin/tensorfold-native serve "$model_dir" \
      --name Qwen3.8-Flash-Next --host 127.0.0.1 --port "$APORT" \
      "${ARGS[@]}" >/dev/null
  log "CMD $arm $(printf '%q ' "${NSYS[@]}" /usr/local/bin/tensorfold-native serve "$model_dir" --name Qwen3.8-Flash-Next --host 127.0.0.1 --port "$APORT" "${ARGS[@]}" | cut -c1-400)"
  if [ $? != 0 ]; then log "BOOT $arm docker run failed"; return 1; fi
  # wait for the off-port serve to answer; bail at once if the container exits
  local i
  for i in $(seq 1 144); do
    [ "$(achealthcode)" = 200 ] && break
    [ "$(docker inspect -f '{{.State.Running}}' "$PROFCN" 2>/dev/null)" != true ] && break
    sleep 5
  done
  if [ "$(achealthcode)" != 200 ]; then
    log "BOOT $arm not ready ahealth $(achealthcode)"
    docker logs "$PROFCN" >> "$d/prof-server.log" 2>&1 || true
    docker rm -f "$PROFCN" >/dev/null 2>&1 || true; return 1
  fi
  capture "$arm" "$d" "$PROFCN" "$APORT"
  # drive the trace: one stream, greedy, fixed step count, then stop the container mid-decode so nsys flushes
  trace "$d" "$steps" || log "TRACE $arm rc $rc"
  # allow nsys to flush: stop the container (the report is written on exit)
  docker stop -t 200 "$PROFCN" >> "$LOG" 2>&1 || true
  sleep 5
  docker logs "$PROFCN" > "$d/prof-server.log" 2>&1 || true
  docker rm -f "$PROFCN" >/dev/null 2>&1 || true
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN{printf "wall_s %.1f\n", b-a}' >> "$d/gpu.txt"
  log "PROFILE-DONE $arm nsout $nsout $(ls -la "$nsout"* 2>/dev/null | head -2 | tr '\n' ' ')"
  return 0
}

# analyse the nsys report: kernel table (name, instances, total ms, mean us) + the cudaMemcpy table
analyse_nsys() {
  local arm=$1 d=$2 nsout=$3
  local rep="${nsout}.nsys-rep"
  [ -f "$rep" ] || rep=$(ls "${nsout}"*.nsys-rep 2>/dev/null | head -1)
  if [ -z "${rep:-}" ] || [ ! -f "$rep" ]; then log "NSYS $arm no report at $nsout"; return 1; fi
  python3 "$BOX/nsys_sum.py" "$rep" > "$d/kernels.txt" 2> "$d/kernels.err"
  log "NSYS $arm report $rep -> $(wc -l < "$d/kernels.txt") lines $(head -1 "$d/kernels.txt" 2>/dev/null)"
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
      stop_cn "$CN" "$D_RECIPE"; stop_cn "$CN" "$P_RECIPE"
      ( env -u IMAGE LOCK_HOLDER=0 "$PROD_START" ) >> "$LOG" 2>&1
      wait_health || log "RESTORE health wait timed out"
      ;;
  esac
  mkdir -p "$OUT/restored"
  docker inspect "$CN" > "$OUT/restored/prod-inspect.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/restored/image.txt" 2>/dev/null || true
  curl -s --max-time 10 "$URL/health" > "$OUT/restored/health.json" 2>/dev/null || true
  python3 "$GATE/check-prod-env.py" --inspect "$OUT/restored/prod-inspect.json" > "$OUT/restored/envcheck.txt" 2>&1
  erc=$?
  log "RESTORED health $(healthcode) image $(cat "$OUT/restored/image.txt" 2>/dev/null) envcheck rc $erc :: $(tail -1 "$OUT/restored/envcheck.txt" 2>/dev/null)"
}
final_exit() {
  [ "${EXITING:-0}" = 1 ] && return 0
  EXITING=1
  restore_production
  log "EXIT-DONE $(date -Is) health $(healthcode) image $(docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null)"
}
trap final_exit EXIT
trap 'exit 130' INT TERM HUP

log "START $(date -Is) OUT $OUT driver $(sha256sum "$SELF" | cut -d' ' -f1) STEPS $STEPS"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); nvidia-smi $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader)"
log "PAYLOAD $(cd "$BOX" && sha256sum trace_decode.py nsys_sum.py prompt1.txt 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"
for arm in P D; do docker image inspect "$(tag_of "$arm")" -f '{{.Id}}' > "$OUT/phase0-$arm.txt" 2>&1 || true; log "PREFLIGHT image $arm $(cat "$OUT/phase0-$arm.txt") expected $(id_of "$arm")"; done
stop_cn "$CN" "$P_RECIPE"
log "STOPPED production $(date -Is) health $(healthcode) mem_avail $(memavail)"

for arm in ${ARMS:-P D}; do
  [ "$arm" = D ] && clear_dstore
  d=$OUT/$arm
  boot_profile "$arm" "$d" "$d/${arm}" "$STEPS" || { log "CELL-FAILED $arm"; continue; }
  analyse_nsys "$arm" "$d" "$d/${arm}"
  # summary of the stage table from the prof server log
  grep -aE 'rounds rank 0 decode|rounds rank 0 .*: [0-9]+ rounds|mtp level' "$d/prof-server.log" > "$d/rounds.txt" 2>/dev/null || true
  grep -aE 'profile rank 0 chunk 0' "$d/prof-server.log" > "$d/prefill.txt" 2>/dev/null || true
  log "ROUNDS $arm $(wc -l < "$d/rounds.txt") lines $(head -1 "$d/rounds.txt" 2>/dev/null)"
  log "CELL-DONE $arm elapsed $(elapsed_min) min"
done
cp "$SELF" "$OUT/driver.sh" 2>/dev/null || true
log "RUN-DONE $(date -Is) elapsed $(elapsed_min) min"
log "PROFILE-DONE $(date -Is) cells $(find "$OUT" -name 'rounds.txt' | wc -l)"
