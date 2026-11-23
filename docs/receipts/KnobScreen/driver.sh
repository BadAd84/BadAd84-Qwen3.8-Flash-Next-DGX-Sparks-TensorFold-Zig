#!/usr/bin/env bash
# driver.sh [dry|run|restore|clean] - the KnobScreen window on spark6.
#
# A screen, never a verdict: per candidate three boots in the order control, candidate, control, one arm a boot,
# each a fresh boot of the pinned r5 FP4 dev image through the recipe launcher with a copy of the committed
# dev.env (the candidate's copy differs in exactly one line). Cells: decode at 1 and 4 streams on the prose and
# code prompts at temperature 0, one sampled 4-stream cell (temperature 1.0, the only cell that reaches
# SAMPLED_HEADS) and cold TTFT at 2k and 32k. One record a boot in $OUT/<arm>/<role>/meta.json beside the tools'
# own conc.json and ttft.txt.
#
# The launcher is $RECIPE/start.sh (the rpr recipe), NOT $HOME/qwen6-start.sh: that script execs production's own
# TF_FLASHNEXT block over the inherited environment, which would replace the arm. The recipe passes every
# TENSORFOLD_*/TF_FLASHNEXT_* name that is SET in its own environment (start.sh:169-172), and an `export NAME`
# with no value is absent from `env`, so presence-default settings stay absent.
#
# The GPU lock is taken with flock; production is stopped after the lock (and after EnvBoot's r5 prompt-following
# verdict is on disk as $BOX/GATE) and restored from the EXIT trap, gated on /health 200 and the pinned
# production image id (PROD-IMAGE-OK). The window is capped at 8 hours from lock acquisition. A preflight boot
# with cells must pass before any arm runs, so a bad shape costs one boot, not thirty-six.
set -u
SELF=$(readlink -f "$0")
BOX=${KS_BOX:-$HOME/work/KnobScreen}
OUT=${KS_OUT:-$BOX/out}
H=$BOX/harness
REF=$BOX/ref
ENVD=$BOX/env
URL=http://127.0.0.1:8888
PORT=8888
CN=qwen38-flash-next-tf
DEV_IMAGE=tensorfold-qwen38:qr-a-r5-1ece6e6db
DEV_IMAGE_ID=sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063
PROD_IMAGE=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
PROD_ID=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
RECIPE=${RECIPE:-$HOME/work/lanes/rpr/recipe}
PROD_START=${PROD_START:-$HOME/qwen6-start-prod.sh}
LOCK=$HOME/work/gpu.lock
SPEC='conc:levels=1,4,tokens=256,reps=3,temps=0,1.0,seed=1234;ttft:sizes=2k,32k,thinking=off,loads=idle,reps=3,max_tokens=16,warm_add=0'
BUDGET_S=$((8 * 3600))
MODE=${1:-run}
mkdir -p "$OUT" "$ENVD"
LOG=$OUT/run.log
log() { echo "$(date -Is) $*" >> "$LOG"; }
now() { date -Is; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw --format=csv,noheader 2>/dev/null | tr -d ' '; }
memavail() { awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo; }
free_gib() { df --output=avail -BG "$HOME" | tail -1 | tr -dc '0-9'; }
wait_mem() { local i; for i in $(seq 1 90); do [ "$(memavail)" -ge 14 ] && return 0; sleep 10; done; return 1; }
health() { curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health" 2>/dev/null; }
mm() { curl -s --max-time 5 "$URL/v1/models" | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])' 2>/dev/null; }
foreign() { docker logs --tail 20000 "$CN" 2>&1 | grep -aE '"(GET|POST) /' | grep -avE '127\.0\.0\.1|\[::1\]' | wc -l; }
imgof() { docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' 2>/dev/null || true; }
digest() {
  { sha256sum "$H"/*.py | awk '{print $1}' | sort; printf '%s\n' "$SPEC"; } | sha256sum | cut -d' ' -f1
}

dash_find() {
  local n
  for n in sparkdash spark-dash sparkDash; do
    systemctl --user is-active "$n" >/dev/null 2>&1 && { echo "user:$n"; return; }
    systemctl is-active "$n" >/dev/null 2>&1 && { echo "system:$n"; return; }
  done
  n=$(docker ps --format '{{.Names}}' 2>/dev/null | grep -i dash | head -1 || true)
  [ -n "$n" ] && { echo "docker:$n"; return; }
  echo none
}
dash_stop() {
  case "$1" in
  user:*) systemctl --user stop "${1#user:}" >> "$LOG" 2>&1 && log "DASH stopped user ${1#user:}" || log "DASH-KEPT user ${1#user:}";;
  system:*) systemctl stop "${1#system:}" >> "$LOG" 2>&1 && log "DASH stopped system ${1#system:}" || log "DASH-KEPT system ${1#system:}";;
  docker:*) docker stop "${1#docker:}" >> "$LOG" 2>&1 && log "DASH stopped docker ${1#docker:}" || log "DASH-KEPT docker ${1#docker:}";;
  *) log "DASH none found; request accounting is the guard (foreign must be 0)";;
  esac
}
dash_start() {
  case "${1:-none}" in
  user:*) systemctl --user start "${1#user:}" >> "$LOG" 2>&1 || true;;
  system:*) systemctl start "${1#system:}" >> "$LOG" 2>&1 || true;;
  docker:*) docker start "${1#docker:}" >> "$LOG" 2>&1 || true;;
  esac
  log "DASH restored ${1:-none}"
}

stop_dev() {
  ( cd "$RECIPE" && ./stop.sh ) >> "$LOG" 2>&1 || true
  local i
  for i in $(seq 1 30); do
    [ -z "$(docker ps -q --filter "name=^${CN}$" 2>/dev/null)" ] && break
    sleep 2
  done
  log "DEV-STOP /health $(health) containers [$(docker ps --format '{{.Names}}' 2>/dev/null | tr '\n' ' ')] mem $(memavail) GiB"
}

restore() {
  local rc=0 code=000 pimg="" i
  if [ "${STOPPED_PROD:-0}" != 1 ]; then
    log "RESTORE skipped: this window never stopped production (/health $(health))"
    echo "prod untouched /health $(health) at $(now)" > "$OUT/production.txt"
    dash_start "${DASH_STATE:-none}"
    return 0
  fi
  stop_dev
  ( env -u IMAGE LOCK_HOLDER=0 IMAGE="$PROD_IMAGE" "$PROD_START" </dev/null ) > "$OUT/restore.log" 2>&1 || rc=$?
  for i in $(seq 1 240); do code=$(health); [ "$code" = 200 ] && break; sleep 5; done
  pimg=$(imgof)
  case "$pimg" in
  *"$PROD_IMAGE"*"$PROD_ID"*) echo "prod /health $code rc $rc image $pimg" > "$OUT/production.txt"; echo "PROD-IMAGE-OK" >> "$OUT/production.txt"; log "RESTORE ok $code $pimg";;
  *) echo "prod /health $code rc $rc image ${pimg:-absent}" > "$OUT/production.txt"; log "RESTORE-BAD health $code image ${pimg:-absent}";;
  esac
  curl -s --max-time 10 "$URL/health" > "$OUT/health-restored.json" 2>/dev/null || true
  dash_start "${DASH_STATE:-none}"
  echo "home $(du -sh "$HOME" 2>/dev/null | cut -f1) at $(now)" >> "$OUT/home.txt"
}

boot_role() { # arm role envfile -> 0 ok; writes meta.json, env.txt, settings.txt, boot.log
  local arm=$1 role=$2 envfile=$3 d="$OUT/$1/$2" rc=0 t0 wall code model envsha settings_ok=0 img_ok=0
  mkdir -p "$d"
  rm -f "$d/meta.json"
  if ! wait_mem; then log "MEM-LOW $arm/$role $(memavail) GiB"; return 1; fi
  if [ "$(free_gib)" -lt 40 ]; then log "DISK-LOW $arm/$role $(free_gib) GiB"; return 1; fi
  envsha=$(sha256sum "$envfile" | cut -d' ' -f1)
  echo "gpu_before $(gpu)" > "$d/thermal.txt"
  t0=$(date +%s)
  ( set -a; . "$envfile"; set +a
    cd "$RECIPE"
    timeout 2400 env PREPARE=0 IMAGE="$DEV_IMAGE" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=8 CONTEXT=262144 \
      HOST=127.0.0.1 PORT="$PORT" MEM_CHECK=0 THINKING=0 DRAFTS=1 WAIT_TIMEOUT=1800 \
      ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1 || rc=$?
  wall=$(( $(date +%s) - t0 ))
  code=000; model=""
  if [ "$rc" = 0 ]; then
    local i
    for i in $(seq 1 180); do
      code=$(health); model=$(mm)
      [ "$code" = 200 ] && [ -n "$model" ] && break
      sleep 10
    done
  fi
  imgof > "$d/container-image.txt"
  docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CN" 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)[A-Z0-9_]*=' | sort > "$d/env.txt" || true
  if [ -s "$d/env.txt" ]; then
    python3 "$BOX/check_env.py" "$envfile" "$d/env.txt" > "$d/settings.txt" 2>&1 || true
    settings_ok=$(grep -c 'SETTINGS-OK' "$d/settings.txt" 2>/dev/null || true)
    [ "$settings_ok" = 1 ] || log "SETTINGS $arm/$role $(grep -v 'SETTINGS-OK' "$d/settings.txt" | tr '\n' '|' | cut -c1-300)"
  fi
  docker logs --tail 20000 "$CN" > "$d/server.log" 2>&1 || true
  echo "gpu_after $(gpu)" >> "$d/thermal.txt"
  if grep -q "$DEV_IMAGE_ID" "$d/container-image.txt" 2>/dev/null; then img_ok=1; fi
  if [ "$img_ok" != 1 ]; then
    log "IMG-FAILED $arm/$role: the container image is \"$(cat "$d/container-image.txt" 2>/dev/null)\" not $DEV_IMAGE_ID"
    return 3
  fi
  python3 "$BOX/rec.py" "$d/meta.json" \
    arm="$arm" role="$role" boot_rc="$rc" health="$code" model="${model:-none}" digest="$(digest)" \
    env_sha="$envsha" boot_wall_s="$wall" foreign="$(foreign)" img_ok="$img_ok" \
    settings_ok="${settings_ok:-0}" temp="$(sed -n 's/^gpu_after //p' "$d/thermal.txt")"
  log "BOOT $arm/$role rc $rc health $code wall ${wall}s model ${model:-none} settings ${settings_ok:-0} foreign $(foreign) gpu $(gpu)"
  if [ "${settings_ok:-0}" != 1 ]; then
    log "SETTINGS-FAILED $arm/$role: the arm did not reach the container, so its cells measure nothing"
    return 2
  fi
  [ "$rc" = 0 ] && [ "$code" = 200 ] && [ -n "$model" ]
}

cells() { # arm role -> both clients into the boot's own dir
  local arm=$1 role=$2 d="$OUT/$1/$2" rc=0 model
  model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$d/meta.json")
  python3 "$H/bench_concurrent.py" "$URL" "$model" --tokens 256 --reps 3 --levels 1,4 --temperatures 0,1.0 \
    --seed 1234 --alone --serial --label "$arm-$role" --output "$d/conc.json" > "$d/conc.txt" 2>&1 || rc=$?
  python3 "$H/ttft.py" "$PORT" --host 127.0.0.1 --model "$model" --sizes 2k,32k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 > "$d/ttft.txt" 2>&1 || rc=$?
  log "CELLS $arm/$role rc $rc gpu $(gpu)"
  return $rc
}

one_boot() { # arm role envfile
  local arm=$1 role=$2 envfile=$3 attempt
  if [ "$role" = a ]; then
    python3 "$BOX/mkenv.py" "$REF/dev.env" "$ARM_NAME" "$ARM_VALUE" "$envfile" > "$OUT/$arm/mkenv.txt" 2>&1 \
      || { log "MKENV-FAILED $arm"; echo "MKENV-FAILED" > "$OUT/$arm/mkenv.txt"; return 1; }
  else
    cp "$REF/dev.env" "$envfile"
  fi
  local brc=0
  for attempt in 1 2; do
    stop_dev
    brc=0
    boot_role "$arm" "$role" "$envfile" || brc=$?
    if [ "$brc" = 0 ]; then
      cells "$arm" "$role" || log "CELLS-FAILED $arm/$role attempt $attempt"
      return 0
    fi
    log "BOOT-FAILED $arm/$role attempt $attempt (status $brc)"
    case "$brc" in
    2|3) log "BOOT-NO-RETRY $arm/$role: a settings or image refusal repeats on a fresh boot"; return 1;;
    esac
  done
  return 1
}

preflight() { # one control boot and its cells, before any arm
  local d=$OUT/preflight rc=0
  mkdir -p "$d"
  cp "$REF/dev.env" "$ENVD/control.env"
  stop_dev
  if ! boot_role preflight c1 "$ENVD/control.env"; then
    log "PREFLIGHT-BOOT-FAILED $(tail -3 "$d/c1/boot.log" 2>/dev/null | tr '\n' ' ')"
    echo PREFLIGHT-BOOT-FAILED > "$OUT/RUN-STOP"
    return 1
  fi
  if ! cells preflight c1; then
    log "PREFLIGHT-CELLS-FAILED"
    echo PREFLIGHT-CELLS-FAILED > "$OUT/RUN-STOP"
    return 1
  fi
  log "PREFLIGHT-OK $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["model"], d["boot_wall_s"])' "$d/c1/meta.json" 2>/dev/null)"
  stop_dev
  return 0
}

run_arm() { # arm name value
  local arm=$1 name=$2 value=$3 d="$OUT/$1" role
  ARM_NAME=$name ARM_VALUE=$value
  mkdir -p "$d"
  echo "$name	$value" > "$d/setting.txt"
  for role in c1 a c2; do
    one_boot "$arm" "$role" "$ENVD/$arm-$role.env" || log "ARM-INCOMPLETE $arm/$role"
  done
  log "ARM-DONE $arm $(now)"
}

dry() {
  local D=$BOX/dry spec arm mode role
  rm -rf "$D"; mkdir -p "$D"
  printf '01-attn-lanes\tTF_FLASHNEXT_ATTN_LANES\t1\tA1\tstub\n02-decode-graph\tTF_FLASHNEXT_DECODE_GRAPH\t1\tA1\tstub\n03-window-graph\tTF_FLASHNEXT_WINDOW_GRAPH\t0\tA1\tstub\n04-qmmf-half\tTF_QMMF_HALF_BELOW\t0\tA1\tstub\n07-sampled-heads\tTF_FLASHNEXT_SAMPLED_HEADS\t0\tA1\tstub\n' > "$D/plan-stub.tsv"
  for spec in "01-attn-lanes promote" "02-decode-graph kill" "03-window-graph inside" "04-qmmf-half unstable" "07-sampled-heads promote"; do
    set -- $spec; arm=$1; mode=$2
    for role in c1 a c2; do
      mkdir -p "$D/$arm/$role"
      python3 "$BOX/stub_cells.py" "$D/$arm/$role" "$role" "$mode" > /dev/null
      python3 "$BOX/rec.py" "$D/$arm/$role/meta.json" boot_rc=0 health=200 foreign=0 \
        digest="stubdigest" env_sha="stub" boot_wall_s=1 settings_ok=1
    done
  done
  python3 "$BOX/analyze.py" --out "$D" --plan "$D/plan-stub.tsv" | tee "$D/table.md"
  local out; out=$(cat "$D/table.md")
  for want in PROMOTE KILL INCONCLUSIVE; do
    case "$out" in *"$want"*) echo "DRY has $want";; *) echo "DRY-MISSING $want"; return 1;; esac
  done
  echo DRY-OK
}

# ------------------------------------------------------------------ entry
if [ "$MODE" = clean ]; then
  echo "removing $BOX"; rm -rf "$BOX"; exit 0
fi
if [ "$MODE" = dry ]; then
  dry; exit $?
fi
if [ "$MODE" = restore ]; then
  STOPPED_PROD=1; restore; exit 0
fi

if [ "${KL_LOCKED:-}" != 1 ]; then
  log "WAIT $(now) for $LOCK (holders: $(pgrep -af '[f]lock -o -w 43200 .*gpu.lock' | sed 's/ env .*//' | tr '\n' ' '))"
  flock -o -w 43200 "$LOCK" env KL_LOCKED=1 KS_BOX="$BOX" KS_OUT="$OUT" bash "$SELF" run
  echo "driver exit $? $(now)" >> "$LOG"
  exit 0
fi

date +%s > "$BOX/started"
DEADLINE=$(( $(cat "$BOX/started") + BUDGET_S ))
log "HELD $(now) lock; deadline $(date -Is -d "@$DEADLINE") budget starts here, not at queue time"
for f in "$H/bench_concurrent.py" "$H/ttft.py" "$REF/dev.env" "$RECIPE/start.sh" "$RECIPE/stop.sh"; do
  [ -f "$f" ] || { log "PREFLIGHT-ABORT missing $f"; echo "PREFLIGHT-ABORT $f" > "$OUT/RUN-STOP"; exit 9; }
done
docker image inspect "$DEV_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $DEV_IMAGE absent"; echo "PREFLIGHT-ABORT dev image" > "$OUT/RUN-STOP"; exit 9; }
[ "$(docker image inspect "$DEV_IMAGE" --format '{{.Id}}')" = "$DEV_IMAGE_ID" ] \
  || { log "PREFLIGHT-ABORT dev image id $(docker image inspect "$DEV_IMAGE" --format '{{.Id}}')"; echo "PREFLIGHT-ABORT dev image id" > "$OUT/RUN-STOP"; exit 9; }
docker image inspect "$PROD_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $PROD_IMAGE absent"; echo "PREFLIGHT-ABORT prod image" > "$OUT/RUN-STOP"; exit 9; }

# The gate: EnvBoot's fast r5 prompt-following verdict (Main's FAST-VERDICT marker), or this box's GATE file.
# Absence is never CLEAN: wait up to 20 minutes, then refuse and report, leaving production alone.
EG=$HOME/work/EnvBoot/FAST-VERDICT
i=0
while [ ! -s "$EG" ] && [ ! -s "$BOX/GATE" ] && [ "$i" -lt 40 ]; do sleep 30; i=$((i+1)); done
if [ -s "$BOX/GATE" ]; then GSRC=$BOX/GATE; else GSRC=$EG; fi
if [ ! -s "$GSRC" ]; then
  log "GATE-MISSING: no EnvBoot FAST-VERDICT and no GATE file after $((i * 30)) s; not screening"
  echo "GATE-MISSING" > "$OUT/RUN-STOP"
  exit 7
fi
cp "$GSRC" "$OUT/gate-marker.txt" 2>/dev/null || true
[ -f "$HOME/work/EnvBoot/RESULT.md" ] && cp "$HOME/work/EnvBoot/RESULT.md" "$OUT/gate-result.md" 2>/dev/null || true
FIRST=$(head -1 "$GSRC" 2>/dev/null | tr -d '\r')
if ! printf '%s' "$FIRST" | grep -qiE '^(verdict:[[:space:]]*)?clean\b'; then
  log "GATE-BLOCKED: first line [$FIRST]; $(head -4 "$GSRC" | tr '\n' ' ' | cut -c1-300); not screening"
  echo "GATE-BLOCKED $FIRST" > "$OUT/RUN-STOP"
  exit 8
fi
log "GATE pass from $GSRC: $(tr '\n' ' ' < "$GSRC" | cut -c1-400)"
if [ ! -f "$BOX/GO" ]; then
  log "GATE-NO-GO: Main's GO file is absent (the int4 device receipt has not landed); not screening"
  echo "GATE-NO-GO" > "$OUT/RUN-STOP"
  exit 10
fi
log "GO present: $(head -3 "$BOX/GO" | tr '\n' ' ' | cut -c1-200)"

prod_before() { # prove production is restorable on the pinned image before the window spends itself
  local code img i
  code=$(health); img=$(imgof)
  case "$img" in
  *"$PROD_IMAGE"*"$PROD_ID"*)
    [ "$code" = 200 ] && { echo "found-up health 200 image $img" > "$OUT/prod-before.txt"; log "PROD-BEFORE ok health 200 $img"; return 0; } ;;
  esac
  log "PROD-BEFORE not serving (health $code image ${img:-absent}): starting it to prove the restore works"
  ( env -u IMAGE LOCK_HOLDER=0 IMAGE="$PROD_IMAGE" "$PROD_START" </dev/null ) > "$OUT/prod-before.log" 2>&1 || true
  for i in $(seq 1 240); do code=$(health); [ "$code" = 200 ] && break; sleep 5; done
  img=$(imgof)
  case "$img" in
  *"$PROD_IMAGE"*"$PROD_ID"*)
    [ "$code" = 200 ] && { echo "started-by-guard health 200 image $img" > "$OUT/prod-before.txt"; log "PROD-BEFORE proven restorable by the guard health 200 $img"; return 0; } ;;
  esac
  log "PROD-BEFORE-BAD health $code image ${img:-absent}: refusing the window rather than risk an unrestorable end"
  echo "failed health $code image ${img:-absent}" > "$OUT/prod-before.txt"
  echo "PROD-BEFORE-BAD health $code" > "$OUT/RUN-STOP"
  return 1
}

echo "home $(du -sh "$HOME" 2>/dev/null | cut -f1) at $(now)" > "$OUT/home.txt"
DASH_STATE=$(dash_find)
log "START $(now) digest $(digest) dash $DASH_STATE"
trap restore EXIT
trap 'exit 130' INT TERM HUP
prod_before || exit 5
stop_dev
dash_stop "$DASH_STATE"
STOPPED_PROD=1
log "PROD-STOPPED /health $(health) image $(imgof) mem $(memavail) GiB gpu $(gpu)"

preflight || exit 6

while IFS=$'\t' read -r arm name value tier why; do
  [ -n "${arm:-}" ] || continue
  case "$arm" in \#*) continue;; esac
  if [ "$(date +%s)" -ge "$DEADLINE" ]; then
    echo "$arm ($name=$value) left: the 8-hour window closed before its boots" >> "$OUT/LEFT"
    log "SKIP $arm: budget"
    continue
  fi
  log "ARM-START $arm $name=$value tier $tier $(now)"
  run_arm "$arm" "$name" "$value" || true
done < "$BOX/plan.tsv"

python3 "$BOX/analyze.py" --out "$OUT" --plan "$BOX/plan.tsv" > "$OUT/table.md" 2>&1 || true
python3 "$BOX/result.py" --box "$BOX" >> "$LOG" 2>&1 || true
touch "$OUT/RUN-DONE"
log "DONE $(now)"
