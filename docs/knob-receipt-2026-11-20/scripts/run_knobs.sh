#!/usr/bin/env bash
# run_knobs.sh <window> - one GPU window of the knob receipt on spark6: upstream main 1ece6e6db as ONE image
# (tensorfold-qwen38:knob-m-1ece6e6d), every arm the same image and the same environment except one setting.
#
# The base environment is production's own ($HOME/qwen6-start-prod.sh's env block), printed per arm from the
# container's inspect. An arm's overrides are applied on top; an override with an empty value removes that name
# from the base environment (the "unset" arm).
#
# The plan is plans/<window>.tsv, one line an arm:
#   arm <TAB> passes <TAB> parA <TAB> ctxA <TAB> overrides(space separated K=V)
# passes letters: A decode and exactness with the prompt cache on (par 8, 32768-token window);
#                 B cold prompts and the cache-off exactness (par 4, 131072, --prompt-cache-gib 0);
#                 P one stream, cold prompts and decode (par 1, 131072, --prompt-cache-gib 0);
#                 D resume pressure under the prompt cache (par 2, 131072).
#
# Every probe records the server's own request counts before and after it; an arm that saw a request it did not
# send, or whose boot or a probe failed, is rerun once on a fresh boot with its first attempt kept as
# <dir>.rejected1. The GPU lock is held for the whole window (flock, FIFO); production is restored from the EXIT
# trap (qwen6-start-prod.sh with LOCK_HOLDER=0) and /health checked.
set -u
WINDOW=${1:?usage: run_knobs.sh <window>}
SELF=$(readlink -f "$0")
BOX=$HOME/work/KnobTest
OUT=$BOX/out/$WINDOW
URL=http://127.0.0.1:8080
CN=qwen38-flash-next-tf
H=$BOX/harness-tools
MI=knob-m-1ece6e6d
X=$HOME/work/target/exact15
TTFT=$BOX/scripts/ttft.py
PROD_ENV_FILE=$BOX/prod-env.txt
mkdir -p "$OUT"
LOG=$OUT/run.log
log() { echo "$*" >> "$LOG"; }
PLAN=$BOX/plans/$WINDOW.tsv
[ -f "$PLAN" ] || { echo "no plan $PLAN" >&2; exit 1; }

if [ "${DRY:-0}" != 1 ] && [ "${KL_LOCKED:-}" != 1 ]; then
  echo "$(date -Is) waiting for the GPU lock (holders/waiters: $(pgrep -af '[f]lock .*gpu.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env KL_LOCKED=1 bash "$SELF" "$WINDOW"
  echo "run_knobs exit $? $(date -Is)" >> "$LOG"
  exit
fi

gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw --format=csv,noheader | tr -d ' '; }
memavail() { awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo; }
wait_mem() {
  local i
  for i in $(seq 1 90); do
    [ "$(memavail)" -ge 14 ] && return 0
    sleep 10
  done
  return 1
}
metrics() { curl -s --max-time 5 "$URL/metrics" | grep -aE '^[a-z:_]*mtp_(drafted|accepted)_total' | tr '\n' ' '; }
gets() {
  local l paths nonlocal
  l=$(docker logs "$CN" 2>/dev/null)
  paths=$(printf '%s\n' "$l" | grep -aE '"(GET|POST) /' | sed -E 's/.*"((GET|POST) [^ ]+).*/\1/' | sort | uniq -c | tr '\n' ' ')
  nonlocal=$(printf '%s\n' "$l" | grep -aE '"(GET|POST) /' | grep -av -c '^\[tensorfold\] 127\.0\.0\.1 ' || true)
  echo "paths[$paths] nonlocal=${nonlocal:-0}"
}
foreign() { sed -n 's/.*nonlocal=\([0-9][0-9]*\).*/\1/p' "$1/gets.txt" 2>/dev/null | awk '{s+=$1} END{print s+0}'; }
restore() {
  ( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) >> "$LOG" 2>&1 || true
  ( env LOCK_HOLDER=0 "$HOME/qwen6-start-prod.sh" </dev/null ) > "$OUT/prod.out" 2>&1
  local rc=$? code=000 i
  for i in $(seq 1 60); do
    code=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health)
    [ "$code" = 200 ] && break
    sleep 5
  done
  log "RESTORE prod_rc $rc /health $code $(date -Is)"
  echo "prod /health $code (start rc $rc) $(date -Is)" > "$OUT/production.txt"
}

# The base environment: production's own, one K=V a line. Read as an array of arguments.
BASE_ARGS=()
while IFS= read -r line; do
  [ -n "$line" ] && BASE_ARGS+=("$line")
done < "$PROD_ENV_FILE"

log "START $(date -Is) WINDOW $WINDOW image tensorfold-qwen38:$MI"
log "SCRIPT run_knobs.sh sha256 $(sha256sum "$SELF" | cut -d' ' -f1) analyze $(sha256sum "$BOX/scripts/analyze_knobs.py" | cut -c1-16) resume $(sha256sum "$BOX/scripts/resume_bench.py" | cut -c1-16)"
# env_args ARM_OVERRIDES -> the base environment with the arm's overrides applied; NAME= removes NAME.
env_args() {
  local ovs=$1 k v drop=() keep=()
  for kv in $ovs; do
    k=${kv%%=*}; v=${kv#*=}
    if [ -z "$v" ]; then drop+=("$k"); else keep+=("$kv"); fi
  done
  local line name
  for line in "${BASE_ARGS[@]}"; do
    name=${line%%=*}
    local skip=0 d
    for d in "${drop[@]:-}"; do [ "$d" = "$name" ] && skip=1; done
    [ "$skip" = 0 ] && printf '%s\0' "$line"
  done
  local kv
  for kv in "${keep[@]:-}"; do
    [ -n "$kv" ] || continue
    name=${kv%%=*}; local skip2=0 d2
    for d2 in "${drop[@]:-}"; do [ "$d2" = "$name" ] && skip2=1; done
    for line in "${BASE_ARGS[@]}"; do [ "${line%%=*}" = "$name" ] && skip2=1; done
    [ "$skip2" = 0 ] && printf '%s\0' "$kv"
  done
}

# DRY=1: print each arm's plan line and the exact start.sh command its boot would run, then stop. No lock, no
# docker, no production, no GPU.
if [ "${DRY:-0}" = 1 ]; then
  echo "DRY plan $PLAN base env vars ${#BASE_ARGS[@]} (from $PROD_ENV_FILE)"
  n=0
  while IFS=$'\t' read -r arm passes parA ctxA ovs; do
    [ -n "${arm:-}" ] || continue
    case "$arm" in \#*) continue;; esac
    n=$((n + 1))
    local_args=()
    while IFS= read -r -d '' e; do local_args+=("$e"); done < <(env_args "${ovs:-}")
    names=$(printf '%s\n' "${local_args[@]}" | sed 's/=.*//' | sort | tr '\n' ' ')
    echo "ARM $arm passes $passes par $parA ctx $ctxA ovs ${ovs:-none} env-vars $(printf '%s\n' "${local_args[@]}" | grep -c .)"
    echo "  names: $names"
    case "$passes" in *P*) echo "  P: one stream at ctx 131072 with --prompt-cache-gib 0";; esac
    case "$passes" in *D*) echo "  D: ctx 131072, cache on, par 2";; esac
    for kv in $ovs; do
      k=${kv%%=*}; v=${kv#*=}
      if [ -z "$v" ]; then
        printf '%s\n' "${local_args[@]}" | grep -qx "$k=.*" && echo "  REMOVE $k FAILED: still present" || echo "  REMOVE $k ok"
      else
        printf '%s\n' "${local_args[@]}" | grep -qx "$kv" && echo "  SET $kv ok" || echo "  SET $kv FAILED"
      fi
    done
  done < "$PLAN"
  echo "DRY arms $n"
  exit 0
fi

log "PLAN $WINDOW [$(tr '\n' ';' < "$PLAN")]"
log "HOST $(uname -r); $(. /etc/os-release; echo "$PRETTY_NAME"); $(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader); RAM $(free -g | awk '/^Mem:/{print $2}') GiB"
if ! docker image inspect "tensorfold-qwen38:$MI" > /dev/null 2>&1; then log "IMAGE $MI missing"; exit 1; fi
log "IMAGE $MI $(docker image inspect -f '{{.Id}} created={{.Created}} kernels={{index .Config.Labels "tf.kernels"}}' "tensorfold-qwen38:$MI")"
trap restore EXIT
trap 'exit 130' INT TERM HUP
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) >> "$LOG" 2>&1 || true
log "STOPPED the existing serve: :8888 $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health); mem_avail $(memavail) GiB; gpu $(gpu)"

rm -rf "$H" && mkdir -p "$H"
for f in bench_openai.py bench_concurrent.py bench_cache.py bench_stream.py bench_evidence.py bench_metrics.py \
         bench_timing.py bench_thinking.py bench_auth.py bench_args.py; do
  [ -f "$BOX/MAIN/src/tools/$f" ] && cp "$BOX/MAIN/src/tools/$f" "$H"/
done
cp "$BOX/scripts/resume_bench.py" "$H"/
log "HARNESS tools $(cd "$H" && sha256sum *.py | tr '\n' ' ')"
[ -x "$H/bench_concurrent.py" ] || true

boot() { # dir image par ctx overrides extra...
  local d=$1 img=$2 par=$3 ctx=$4 ovs=$5
  shift 5
  local rc=0 t0 t1 mem
  local -a envs=()
  while IFS= read -r -d '' e; do envs+=("$e"); done < <(env_args "$ovs")
  mkdir -p "$d"
  if ! wait_mem; then log "MEM-LOW $d mem_avail $(memavail) GiB below the 14 GiB floor; not booting"; echo "boot_rc 3" > "$d/boot_time.txt"; return 1; fi
  mem=$(memavail)
  { echo "gpu $(gpu)"; echo "mem_avail_gib $mem"; echo "ctx $ctx"; echo "par $par"; echo "overrides ${ovs:-none}"; } > "$d/boot_time.txt"
  t0=$(date +%s.%N)
  ( cd "$HOME/work/lanes/rpr/recipe" && timeout 1800 env "${envs[@]}" PREPARE=0 IMAGE="tensorfold-qwen38:$img" \
      CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL="$par" CONTEXT="$ctx" \
      HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 ./start.sh restart "$@" </dev/null ) > "$d/boot.log" 2>&1 || rc=$?
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN{printf "wall_s %.2f\n", b-a}' >> "$d/boot_time.txt"
  echo "boot_rc $rc" >> "$d/boot_time.txt"
  { echo "# image tensorfold-qwen38:$img par $par ctx $ctx overrides ${ovs:-none}"
    docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CN" 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort
    docker inspect -f '{{join .Config.Entrypoint " "}} | {{join .Config.Cmd " "}}' "$CN" 2>/dev/null
  } > "$d/env.txt"
  log "BOOT ${d#$OUT/} rc $rc ctx $ctx par $par ovs ${ovs:-none} wall $(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%.1f", b-a}')s $(grep -aoE 'Server answered after [0-9]+s' "$d/boot.log" | head -1) $(date -Is) gpu $(gpu) mem_avail $(memavail)"
  log "MEMLINE ${d#$OUT/} $(docker logs "$CN" 2>&1 | grep -a -m1 -o 'model [0-9.]* GiB[^|]*' | cut -c1-300)"
  docker logs -t "$CN" > "$d/server-timed.log" 2>&1 || true
  grep -aE 'refus|InvalidEnvironment|pockets|solo|chunk|passes of' "$d/server-timed.log" > "$d/check.txt" 2>/dev/null || true
  log "CHECK ${d#$OUT/} $(tr '\n' '|' < "$d/check.txt" | cut -c1-400)"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s --max-time 10 "$URL/v1/models" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null)
  [ -n "${MODEL:-}" ] || { log "MODEL empty ${d#$OUT/}"; return 1; }
  log "MODEL $MODEL"
}
down() {
  local d=$1
  docker logs "$CN" > "$d/server.log" 2>&1 || true
  echo "final $(gets)" >> "$d/gets.txt"
  ( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) >> "$LOG" 2>&1 || true
  log "DOWN ${d#$OUT/} foreign $(foreign "$d") $(date -Is) gpu $(gpu)"
}
probe() { # dir name command...
  local d=$1 name=$2 rc=0
  shift 2
  echo "$name before $(metrics)" >> "$d/metrics.txt"
  echo "$name before $(gets)" >> "$d/gets.txt"
  echo "$name gpu_before $(gpu)" >> "$d/gpu.txt"
  "$@" > "$d/$name.out" 2>&1 || rc=$?
  echo "$name after $(metrics)" >> "$d/metrics.txt"
  echo "$name after $(gets)" >> "$d/gets.txt"
  echo "$name gpu_after $(gpu)" >> "$d/gpu.txt"
  log "PROBE ${d#$OUT/} $name rc $rc $(date -Is) gpu $(gpu)"
  return $rc
}
arm_ok() { # dir probe_rc -> 0 ok, 1 boot, 2 foreign requests, 3 probe rc
  local d=$1 prc=${2:-0}
  [ "$prc" = 0 ] || return 3
  grep -q '^boot_rc 0' "$d/boot_time.txt" 2>/dev/null || return 1
  [ "$(foreign "$d")" = 0 ] || return 2
  return 0
}

pass_a() { # dir par ctx
  local d=$1 par=$2 ctx=$3 prc=0
  probe "$d" openai_t0 python3 "$H/bench_openai.py" "$URL" "$MODEL" --tokens 256 --reps 3 \
    --temperatures 0 --label "$(basename "$d")" --output "$d/openai_t0.json" || prc=$?
  probe "$d" conc_t0 python3 "$H/bench_concurrent.py" "$URL" "$MODEL" --tokens 256 --reps 3 \
    --levels 1,2,4,6,8 --alone --serial --temperatures 0 --label "$(basename "$d")" \
    --output "$d/conc_t0.json" || prc=$?
  probe "$d" conc_t1 python3 "$H/bench_concurrent.py" "$URL" "$MODEL" --tokens 128 --reps 2 \
    --levels 1,2,4,6 --alone --serial --temperatures 1.0,0 --label "$(basename "$d")" \
    --output "$d/conc_t1.json" || prc=$?
  probe "$d" golden python3 "$H/bench_concurrent.py" "$URL" "$MODEL" --tokens 256 --reps 1 --temperatures 0 \
    --levels 1,2,4,6 --prompts "$X/golden.json" --alone --serial --label golden --output "$d/golden.json" || prc=$?
  probe "$d" drafts python3 "$X/served_exactness.py" drafts "$URL" "$MODEL" "$X/prompts.json" "$d/drafts.json" || prc=$?
  probe "$d" turns python3 "$X/served_exactness.py" turns "$URL" "$MODEL" "$X/turns.json" "$d/turns.json" || prc=$?
  return $prc
}
pass_b() { # dir on-dir(optional)
  local d=$1 on=${2:-} prc=0
  probe "$d" ttft python3 "$TTFT" 8080 --host 127.0.0.1 --model "$MODEL" --sizes 2k,8k,32k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 || prc=$?
  probe "$d" ttft64 python3 "$TTFT" 8080 --host 127.0.0.1 --model "$MODEL" --sizes 64k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 || prc=$?
  probe "$d" cache python3 "$H/bench_cache.py" "$URL" "$MODEL" --tokens 64 --repeats 2 --streams 2 \
    --require-cold --output "$d/cache.json" || prc=$?
  if [ -n "$on" ] && [ -f "$on/turns.json" ]; then
    probe "$d" fresh python3 "$X/served_exactness.py" fresh "$URL" "$MODEL" "$on/turns.json" "$d/fresh.json" || prc=$?
  fi
  probe "$d" drafts_off python3 "$X/served_exactness.py" drafts "$URL" "$MODEL" "$X/prompts.json" "$d/drafts.json" || prc=$?
  return $prc
}
pass_p() { # dir
  local d=$1 prc=0
  probe "$d" ttft python3 "$TTFT" 8080 --host 127.0.0.1 --model "$MODEL" --sizes 2k,8k,32k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 || prc=$?
  probe "$d" ttft64 python3 "$TTFT" 8080 --host 127.0.0.1 --model "$MODEL" --sizes 64k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 || prc=$?
  probe "$d" conc_t0 python3 "$H/bench_concurrent.py" "$URL" "$MODEL" --tokens 256 --reps 3 \
    --levels 1 --alone --serial --temperatures 0 --label "$(basename "$d")" --output "$d/conc_t0.json" || prc=$?
  probe "$d" drafts python3 "$X/served_exactness.py" drafts "$URL" "$MODEL" "$X/prompts.json" "$d/drafts.json" || prc=$?
  return $prc
}
pass_d() { # dir
  local d=$1 prc=0
  probe "$d" resume python3 "$H/resume_bench.py" "$URL" "$MODEL" --tokens 9000 --against 14 --after 10 \
    --output "$d/resume.json" || prc=$?
  probe "$d" conc_t0 python3 "$H/bench_concurrent.py" "$URL" "$MODEL" --tokens 256 --reps 3 \
    --levels 1,2,4 --alone --serial --temperatures 0 --label "$(basename "$d")" --output "$d/conc_t0.json" || prc=$?
  return $prc
}

run_arm() { # arm passes parA ctxA overrides
  local arm=$1 passes=$2 parA=$3 ctxA=$4 ovs=$5 d=$OUT/$1
  local st prc attempt sub
  for attempt in 1 2; do
    rm -rf "$d"
    prc=0
    st=0
    case "$passes" in
    *A*)
      if boot "$d/a" "$MI" "$parA" "$ctxA" "$ovs"; then pass_a "$d/a" "$parA" "$ctxA" || prc=$?; else st=1; fi
      down "$d/a"
      arm_ok "$d/a" "$prc"; st=$?
      ;;
    esac
    if [ "$st" = 0 ] && [[ "$passes" == *B* ]]; then
      prc=0
      if boot "$d/b" "$MI" 4 131072 "$ovs" --prompt-cache-gib 0; then pass_b "$d/b" "$d/a" || prc=$?; else st=1; fi
      down "$d/b"
      arm_ok "$d/b" "$prc"; st=$?
    fi
    if [ "$st" = 0 ] && [[ "$passes" == *P* ]]; then
      prc=0
      if boot "$d/p" "$MI" 1 131072 "$ovs" --prompt-cache-gib 0; then pass_p "$d/p" || prc=$?; else st=1; fi
      down "$d/p"
      arm_ok "$d/p" "$prc"; st=$?
    fi
    if [ "$st" = 0 ] && [[ "$passes" == *D* ]]; then
      prc=0
      if boot "$d/d" "$MI" 2 131072 "$ovs"; then pass_d "$d/d" || prc=$?; else st=1; fi
      down "$d/d"
      arm_ok "$d/d" "$prc"; st=$?
    fi
    [ "$st" = 0 ] && { log "ARM-OK $arm $(date -Is)"; return 0; }
    log "ARM-RETRY $arm attempt $attempt status $st (1 boot, 2 foreign, 3 probe); rerunning on fresh boots"
    mv "$d" "$d.rejected$attempt"
  done
  log "ARM-FAILED $arm after 2 attempts"
  return 1
}

while IFS=$'\t' read -r arm passes parA ctxA ovs; do
  [ -n "${arm:-}" ] || continue
  case "$arm" in \#*) continue;; esac
  log "ARM-START $arm passes $passes par $parA ctx $ctxA ovs ${ovs:-none} $(date -Is)"
  run_arm "$arm" "$passes" "$parA" "$ctxA" "${ovs:-}"
done < "$PLAN"

log "FOREIGN-SUMMARY $(for d in "$OUT"/*/*; do [ -d "$d" ] && echo "${d#$OUT/}=$(foreign "$d")"; done | tr '\n' ' ')"
touch "$OUT/RUN-DONE"
log "DONE $(date -Is)"
