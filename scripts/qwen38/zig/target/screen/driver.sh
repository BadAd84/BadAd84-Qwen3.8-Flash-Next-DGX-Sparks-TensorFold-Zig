#!/usr/bin/env bash
# driver.sh [dry|run|restore|clean] - the KnobScreen window on spark6.
#
# A screen, never a verdict: per candidate boots in the order control, candidate, control, one arm a boot,
# each a fresh boot of the pinned r5 FP4 dev image through the recipe launcher with the screen base. The base
# is the committed scripts/qwen38/zig/target/env/dev.env, copied at start with its sha256 recorded, filtered
# to the lines the launcher's own name filter can carry (the rest are commented and listed, and an arm on one
# of them is refused before any boot). Cells: decode at 1 and 4 streams on the prose and code prompts at
# temperature 0, one sampled 4-stream cell (the only cell that reaches SAMPLED_HEADS) and cold TTFT at 2k and
# 32k. One record a boot in $OUT/<arm>/<role>/meta.json beside the tools' own conc.json and ttft.txt.
#
# The launcher is $RECIPE/start.sh (the rpr recipe), NOT $HOME/qwen6-start.sh: that script execs production's
# own TF_FLASHNEXT block over the inherited environment, which would replace the arm. start.sh passes every
# TENSORFOLD_*/TF_* name that is SET in its own environment and nothing else (its `env | grep -E
# '^(TENSORFOLD|TF_)[A-Z0-9_]+='` line), so every name of that class is routable and can be an arm; a name
# outside the class is refused before any boot.
#
# The GPU lock is taken with flock; production is stopped after the lock (and after EnvBoot's r5 prompt-
# following verdict is on disk as CLEAN and Main's GO exists) and restored from the EXIT trap, gated on
# /health 200 and the pinned production image id (PROD-IMAGE-OK). The window is capped at 8 hours from lock
# acquisition. The first boot of the window is a discarded warm-up: it proves the serve shape and takes the
# first-boot penalty, and no verdict reads its cells. Then the C-A-C boots; a candidate whose one boot shows a
# single treatment-cell loss gets a second candidate boot (a2) before the window calls it a KILL.
set -u
SELF=$(readlink -f "$0")
BOX=${KS_BOX:-$HOME/work/KnobScreen}
OUT=${KS_OUT:-$BOX/out}
H=${KS_HARNESS:-$BOX/harness}
KIT=${KS_KIT:-$(dirname "$SELF")}
REF=$BOX/ref
ENVD=$BOX/env
REPO_ENV=${KS_REPO_ENV:-$HOME/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig/scripts/qwen38/zig/target/env/dev.env}
REF_SRC=${KS_REF_SRC:-$BOX/refcommitted/dev.env}
PASSES=${KS_PASSES:-'^(TENSORFOLD|TF_)[A-Z0-9_]+$'}
ALLOW=$KIT/allow-extra.txt
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
ALLOW_ARGS=()
mkdir -p "$OUT" "$ENVD"
log() { echo "$(date -Is) $*" >> "$OUT/run.log"; }
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
  user:*) systemctl --user stop "${1#user:}" >> "$OUT/run.log" 2>&1 && log "DASH stopped user ${1#user:}" || log "DASH-KEPT user ${1#user:}";;
  system:*) systemctl stop "${1#system:}" >> "$OUT/run.log" 2>&1 && log "DASH stopped system ${1#system:}" || log "DASH-KEPT system ${1#system:}";;
  docker:*) docker stop "${1#docker:}" >> "$OUT/run.log" 2>&1 && log "DASH stopped docker ${1#docker:}" || log "DASH-KEPT docker ${1#docker:}";;
  *) log "DASH none found; request accounting is the guard (foreign must be 0)";;
  esac
}
dash_start() {
  case "${1:-none}" in
  user:*) systemctl --user start "${1#user:}" >> "$OUT/run.log" 2>&1 || true;;
  system:*) systemctl start "${1#system:}" >> "$OUT/run.log" 2>&1 || true;;
  docker:*) docker start "${1#docker:}" >> "$OUT/run.log" 2>&1 || true;;
  esac
  log "DASH restored ${1:-none}"
}

stop_dev() {
  ( cd "$RECIPE" && ./stop.sh ) >> "$OUT/run.log" 2>&1 || true
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

prepare_ref() { # copy the committed env at start, verified against the pin install.sh wrote; record its sha
  local src sha want
  if [ -f "$REPO_ENV" ]; then src=$REPO_ENV; else src=$REF_SRC; fi
  if [ ! -f "$src" ]; then
    log "REF-MISSING $src (no repo copy and no installed refcommitted copy): not screening"
    echo "REF-MISSING $src" > "$OUT/REF-STOP"
    return 1
  fi
  sha=$(sha256sum "$src" | cut -d' ' -f1)
  if [ -f "$REF_SRC.sha256" ]; then
    want=$(cut -d' ' -f1 "$REF_SRC.sha256")
    if [ "$sha" != "$want" ]; then
      log "REF-SHA-MISMATCH $src sha $sha but the installed pin says $want: the copy is not the committed file"
      echo "REF-SHA-MISMATCH $sha $want" > "$OUT/REF-STOP"
      return 1
    fi
  else
    log "REF-UNPINNED $src: no $REF_SRC.sha256, so the copy cannot be proven to be the committed file"
    echo "REF-UNPINNED" > "$OUT/REF-STOP"
    return 1
  fi
  mkdir -p "$REF"
  cp "$src" "$REF/dev.env" || { log "REF-COPY-FAILED"; return 1; }
  cmp -s "$src" "$REF/dev.env" || { log "REF-COPY-MISMATCH"; echo "REF-COPY-MISMATCH" > "$OUT/REF-STOP"; return 1; }
  printf '%s  %s\n' "$sha" "$src" > "$OUT/ref.txt"
  log "REF $src sha $sha copied to $REF/dev.env"
}

base_filter() { # the base the launcher can carry; the rest commented and listed, never an arm
  mkdir -p "$ENVD"
  if ! python3 "$KIT/basefilter.py" "$REF/dev.env" "$ENVD/base.env" --passes "$PASSES" \
      --report "$OUT/base-not-carried.txt" > "$OUT/base-filter.txt" 2>&1; then
    log "BASE-FILTER-FAILED $(tail -3 "$OUT/base-filter.txt" | tr '\n' ' ')"
    echo BASE-FILTER-FAILED > "$OUT/REF-STOP"
    return 1
  fi
  log "BASE $(head -1 "$OUT/base-filter.txt")"
}

plan_gate() { # PLANFILE: refuse a plan row the launcher cannot carry or that changes nothing, before any boot
  local plan=${1:-$BOX/plan.tsv} bad=0 arm name value tier why hits cur
  : > "$OUT/PASSAGE-REFUSED"
  while IFS=$'\t' read -r arm name value tier why; do
    [ -n "${arm:-}" ] || continue
    case "$arm" in \#*) continue;; esac
    if ! printf '%s' "$name" | grep -qE "$PASSES"; then
      log "PASSAGE-REFUSED $arm $name: the launcher filter $PASSES does not carry the name, so the arm would measure the control twice"
      echo "PASSAGE-REFUSED $arm $name" >> "$OUT/PASSAGE-REFUSED"
      bad=1
      continue
    fi
    hits=$(grep -cE "^export ${name}=" "$ENVD/base.env" || true)
    if [ "$hits" != 1 ]; then
      log "PLAN-BASE $arm $name: $hits export lines in $ENVD/base.env (must be exactly 1)"
      echo "PLAN-BASE $arm $name $hits" >> "$OUT/PASSAGE-REFUSED"
      bad=1
      continue
    fi
    cur=$(sed -n "s/^export ${name}=//p" "$ENVD/base.env" | head -1)
    if [ "$cur" = "$value" ]; then
      log "PLAN-NO-OP $arm $name=$value: the base already states that value, so the arm would measure the control twice"
      echo "PLAN-NO-OP $arm $name=$value" >> "$OUT/PASSAGE-REFUSED"
      bad=1
    fi
  done < "$plan"
  [ "$bad" = 0 ]
}

allow_args() { # the declared launcher and image names the arm file does not state
  local name rest
  ALLOW_ARGS=()
  if [ ! -f "$ALLOW" ]; then
    log "ALLOW-MISSING $ALLOW: without the measured allowlist a strict EXTRA check cannot run"
    echo ALLOW-MISSING > "$OUT/REF-STOP"
    return 1
  fi
  while IFS=' ' read -r name rest; do
    case "${name:-}" in ''|\#*) continue;; esac
    ALLOW_ARGS+=(--allow-extra "$name")
  done < "$ALLOW"
  log "ALLOW $((${#ALLOW_ARGS[@]} / 2)) declared names (recipe config.sh defaults and image ENV)"
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
    if [ "${#ALLOW_ARGS[@]}" -gt 0 ]; then
      python3 "$KIT/check_env.py" "$envfile" "$d/env.txt" "${ALLOW_ARGS[@]}" > "$d/settings.txt" 2>&1 || true
    else
      python3 "$KIT/check_env.py" "$envfile" "$d/env.txt" > "$d/settings.txt" 2>&1 || true
    fi
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
  python3 "$KIT/rec.py" "$d/meta.json" \
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

cells() { # arm role -> both clients into the boot's own dir, after one discarded prime request
  local arm=$1 role=$2 d="$OUT/$1/$2" rc=0 model
  model=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["model"])' "$d/meta.json")
  curl -s --max-time 180 "$URL/v1/chat/completions" -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\",\"messages\":[{\"role\":\"user\",\"content\":\"prime\"}],\"max_tokens\":8,\"temperature\":0}" \
    > "$d/prime.json" 2> "$d/prime.txt" || true
  log "PRIME $arm/$role $(wc -c < "$d/prime.json" 2>/dev/null || echo 0) bytes (discarded, not a cell)"
  python3 "$H/bench_concurrent.py" "$URL" "$model" --tokens 256 --reps 3 --levels 1,4 --temperatures 0,1.0 \
    --seed 1234 --alone --serial --label "$arm-$role" --output "$d/conc.json" > "$d/conc.txt" 2>&1 || rc=$?
  python3 "$H/ttft.py" "$PORT" --host 127.0.0.1 --model "$model" --sizes 2k,32k --thinking off \
    --loads idle --reps 3 --max-tokens 16 --warm-add 0 > "$d/ttft.txt" 2>&1 || rc=$?
  log "CELLS $arm/$role rc $rc gpu $(gpu)"
  return $rc
}

one_boot() { # arm role envfile
  local arm=$1 role=$2 envfile=$3 attempt brc=0
  if [ "$role" = a ] || [ "$role" = a2 ]; then
    python3 "$KIT/mkenv.py" "$ENVD/base.env" "$ARM_NAME" "$ARM_VALUE" "$envfile" --passes "$PASSES" \
      > "$OUT/$arm/mkenv-$role.txt" 2>&1 \
      || { log "MKENV-FAILED $arm/$role $(tail -1 "$OUT/$arm/mkenv-$role.txt")"; return 1; }
  else
    cp "$ENVD/base.env" "$envfile"
  fi
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

inline_verdict() { # arm -> the analyzer's verdict for this arm alone, or empty
  python3 "$KIT/analyze.py" --out "$OUT" --plan "$KIT/plan.tsv" --only "$1" --print-verdict 2>>"$OUT/run.log" \
    | awk -F'\t' -v a="$1" '$1 == "VERDICT" && $2 == a {print $3}'
}

warmup() { # the discarded warm-up boot: proves the serve shape and takes the first-boot penalty
  local d=$OUT/warmup
  mkdir -p "$d"
  cp "$ENVD/base.env" "$ENVD/warmup.env"
  stop_dev
  if ! boot_role warmup w "$ENVD/warmup.env"; then
    log "WARMUP-BOOT-FAILED $(tail -3 "$d/w/boot.log" 2>/dev/null | tr '\n' ' ')"
    echo WARMUP-BOOT-FAILED > "$OUT/RUN-STOP"
    return 1
  fi
  if ! cells warmup w; then
    log "WARMUP-CELLS-FAILED"
    echo WARMUP-CELLS-FAILED > "$OUT/RUN-STOP"
    return 1
  fi
  log "WARMUP-DISCARDED cells $(wc -c < "$d/w/conc.json" 2>/dev/null || echo 0) bytes: no verdict reads them"
  stop_dev
}

run_arm() { # arm name value
  local arm=$1 name=$2 value=$3 d="$OUT/$1" role v
  ARM_NAME=$name ARM_VALUE=$value
  mkdir -p "$d"
  echo "$name	$value" > "$d/setting.txt"
  for role in c1 a c2; do
    one_boot "$arm" "$role" "$ENVD/$arm-$role.env" || log "ARM-INCOMPLETE $arm/$role"
  done
  v=$(inline_verdict "$arm")
  if [ "$v" = KILL-PENDING ]; then
    if [ "$(date +%s)" -lt "$DEADLINE" ]; then
      log "KILL-PENDING $arm: booting a second candidate (a2) to confirm the one-boot loss"
      one_boot "$arm" a2 "$ENVD/$arm-a2.env" || log "ARM-INCOMPLETE $arm/a2"
      v=$(inline_verdict "$arm")
      log "VERDICT $arm ${v:-none} after a2"
    else
      log "KILL-PENDING $arm: the budget closed before the confirm boot, so it stays pending"
    fi
  else
    log "VERDICT $arm ${v:-none}"
  fi
  log "ARM-DONE $arm $(now)"
}

proof() { # name expected actual -> one line, appended to the dry log
  local line
  if [ "$2" = "$3" ]; then
    line="DRY $1 ok [$3]"
  else
    line="DRY $1 FAILED want [$2] got [$3]"
    DRY_FAIL=$((DRY_FAIL + 1))
  fi
  echo "$line"
  echo "$line" >> "$D/proofs.txt"
}

dry() {
  local D=$BOX/dry
  DRY_FAIL=0
  rm -rf "$D"
  mkdir -p "$D/out"
  : > "$D/proofs.txt"

  # 1. REF provenance: the copy is the pinned file; a tampered source is refused.
  mkdir -p "$D/refcommitted"
  printf 'export TF_FLASHNEXT_ATTN_LANES=0\nexport TF_QMMF_HALF_BELOW=96\n' > "$D/refcommitted/dev.env"
  sha256sum "$D/refcommitted/dev.env" | awk '{print $1"  dev.env"}' > "$D/refcommitted/dev.env.sha256"
  ( OUT=$D/out REF=$D/ref REPO_ENV=$D/no-repo REF_SRC=$D/refcommitted/dev.env prepare_ref ) > "$D/ref.log" 2>&1
  proof ref-rc 0 "$?"
  proof ref-sha-recorded "$(cut -d' ' -f1 "$D/refcommitted/dev.env.sha256")" "$(cut -d' ' -f1 "$D/out/ref.txt")"
  cmp -s "$D/refcommitted/dev.env" "$D/ref/dev.env"
  proof ref-copied 0 "$?"
  printf 'export TF_FLASHNEXT_ATTN_LANES=1\n' >> "$D/refcommitted/dev.env"
  ( OUT=$D/out REF=$D/ref REPO_ENV=$D/no-repo REF_SRC=$D/refcommitted/dev.env prepare_ref ) > "$D/ref-tamper.log" 2>&1
  proof ref-tamper-refused 1 "$?"

  # 2. Base filter: a name the launcher cannot carry is commented and reported, an unset line is kept.
  printf '# cite line\nexport TF_FLASHNEXT_ATTN_LANES=0\nexport TF_QMMF_HALF_BELOW=96\nunset TF_ROCE_GID_INDEX\n' > "$D/src.env"
  python3 "$KIT/basefilter.py" "$D/src.env" "$D/base.env" --passes "$PASSES" --report "$D/base-not-carried.txt" > "$D/base-filter.txt" 2>&1
  proof basefilter-rc 0 "$?"
  proof basefilter-carried 1 "$(grep -c '^export TF_FLASHNEXT_ATTN_LANES=0' "$D/base.env")"
  proof basefilter-commented 1 "$(grep -c '^# NOT-CARRIED.*export TF_QMMF_HALF_BELOW=96' "$D/base.env")"
  proof basefilter-unset-kept 1 "$(grep -c '^unset TF_ROCE_GID_INDEX' "$D/base.env")"
  proof basefilter-report 1 "$(grep -c '^TF_QMMF_HALF_BELOW' "$D/base-not-carried.txt")"

  # 3. Passage gate: a plan row the launcher cannot carry is refused before any boot.
  mkdir -p "$D/env"
  cp "$D/base.env" "$D/env/base.env"
  printf '01-ok\tTF_FLASHNEXT_ATTN_LANES\t1\tA1\tdry\n' > "$D/plan-ok.tsv"
  printf '04-bad\tTF_QMMF_HALF_BELOW\t0\tA1\tdry\n' > "$D/plan-bad.tsv"
  printf '09-noop\tTF_FLASHNEXT_ATTN_LANES\t0\tA1\tdry\n' > "$D/plan-noop.tsv"
  ( OUT=$D/out ENVD=$D/env plan_gate "$D/plan-ok.tsv" ) > "$D/plan-ok.log" 2>&1
  proof plan-ok 0 "$?"
  ( OUT=$D/out ENVD=$D/env plan_gate "$D/plan-bad.tsv" ) > "$D/plan-bad.log" 2>&1
  proof plan-passage-refused 1 "$?"
  proof plan-refusal-line 1 "$(grep -c 'PASSAGE-REFUSED 04-bad TF_QMMF_HALF_BELOW' "$D/out/PASSAGE-REFUSED")"
  ( OUT=$D/out ENVD=$D/env plan_gate "$D/plan-noop.tsv" ) > "$D/plan-noop.log" 2>&1
  proof plan-noop-refused 1 "$?"
  proof plan-noop-line 1 "$(grep -c 'PLAN-NO-OP 09-noop TF_FLASHNEXT_ATTN_LANES=0' "$D/out/PASSAGE-REFUSED")"

  # 4. check_env: unset is an absence test, EXTRA fails, a declared extra passes, a value mismatch fails.
  printf 'export TF_A=1\nunset TF_B\n' > "$D/arm.env"
  printf 'TF_A=1\n' > "$D/c-ok.txt"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-ok.txt" > "$D/s-ok.txt" 2>&1
  proof checkenv-unset-absent 0 "$?"
  printf 'TF_A=1\nTF_B=2\n' > "$D/c-present.txt"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-present.txt" > "$D/s-present.txt" 2>&1
  proof checkenv-unset-present 1 "$?"
  proof checkenv-unset-line 1 "$(grep -c '^PRESENT TF_B=2 want unset' "$D/s-present.txt")"
  printf 'TF_A=1\nTF_C=3\n' > "$D/c-extra.txt"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-extra.txt" > "$D/s-extra.txt" 2>&1
  proof checkenv-extra 1 "$?"
  proof checkenv-extra-line 1 "$(grep -c '^EXTRA TF_C=3' "$D/s-extra.txt")"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-extra.txt" --allow-extra TF_C > "$D/s-allow.txt" 2>&1
  proof checkenv-declared-extra 0 "$?"
  printf 'TF_Z=1\n' > "$D/c-absent.txt"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-absent.txt" > "$D/s-absent.txt" 2>&1
  proof checkenv-absent 1 "$?"
  proof checkenv-absent-line 1 "$(grep -c '^ABSENT TF_A=1' "$D/s-absent.txt")"
  printf 'TF_A=9\n' > "$D/c-value.txt"
  python3 "$KIT/check_env.py" "$D/arm.env" "$D/c-value.txt" > "$D/s-value.txt" 2>&1
  proof checkenv-value 1 "$?"
  proof checkenv-value-line 1 "$(grep -c '^VALUE TF_A=9 want 1' "$D/s-value.txt")"

  # 5. Analyzer: one stub arm a verdict branch, plus a discarded warm-up that must not be scored.
  printf '01-promote\tTF_FLASHNEXT_ATTN_LANES\t1\tA1\tstub promote\n02-kill2\tTF_FLASHNEXT_DECODE_GRAPH\t1\tA1\tstub two-cell kill\n03-kill1\tTF_FLASHNEXT_WINDOW_GRAPH\t0\tA1\tstub one-cell kill\n04-kill1c\tTF_FLASHNEXT_BATCH_DRAWS\t0\tA1\tstub confirmed\n05-kill1u\tTF_FLASHNEXT_SHARED_SIDE\t0\tA1\tstub unconfirmed\n06-guard\tTF_FLASHNEXT_PROMPT_BF16\t0\tA2\tstub guard loss\n07-unstable\tTF_FLASHNEXT_READOUT_ROWS\t128\tA2\tstub unstable controls\n08-inside\tTF_FLASHNEXT_FACT_ROWS\t128\tA2\tstub inside\n09-malformed\tTF_FLASHNEXT_WARM_AHEAD\t0\tA2\tstub a malformed boot\n' > "$D/plan-dry.tsv"
  local arm mode
  for arm in 01-promote 02-kill2 03-kill1 04-kill1c 05-kill1u 06-guard 07-unstable 08-inside 09-malformed; do
    mode=inside
    case "$arm" in
    01-promote) mode=promote;; 02-kill2) mode=kill2;; 03-kill1) mode=kill1;;
    04-kill1c) mode=kill1c;; 05-kill1u) mode=kill1;; 06-guard) mode=guard;;
    07-unstable) mode=unstable;; 08-inside) mode=inside;;
    esac
    for role in c1 a c2; do
      mkdir -p "$D/out/$arm/$role"
      python3 "$KIT/stub_cells.py" "$D/out/$arm/$role" "$role" "$mode" > /dev/null
      python3 "$KIT/rec.py" "$D/out/$arm/$role/meta.json" boot_rc=0 health=200 foreign=0 \
        digest=stubdigest env_sha=stub boot_wall_s=1 settings_ok=1
    done
  done
  for arm in 04-kill1c 05-kill1u; do
    mode=inside
    [ "$arm" = 04-kill1c ] && mode=kill1c
    mkdir -p "$D/out/$arm/a2"
    python3 "$KIT/stub_cells.py" "$D/out/$arm/a2" a2 "$mode" > /dev/null
    python3 "$KIT/rec.py" "$D/out/$arm/a2/meta.json" boot_rc=0 health=200 foreign=0 \
      digest=stubdigest env_sha=stub boot_wall_s=1 settings_ok=1
  done
  printf '{"cells": []}\n' > "$D/out/09-malformed/a/conc.json"
  mkdir -p "$D/out/warmup/w"
  python3 "$KIT/stub_cells.py" "$D/out/warmup/w" c1 promote > /dev/null
  python3 "$KIT/rec.py" "$D/out/warmup/w/meta.json" boot_rc=0 health=200 foreign=0 \
    digest=stubdigest env_sha=stub boot_wall_s=1 settings_ok=1
  python3 "$KIT/analyze.py" --out "$D/out" --plan "$D/plan-dry.tsv" --print-verdict > "$D/verdicts.txt" 2>&1
  proof analyze-rc 0 "$?"
  verdict_of() { awk -F'\t' -v a="$1" '$1 == "VERDICT" && $2 == a {print $3}' "$D/verdicts.txt"; }
  proof analyze-promote PROMOTE "$(verdict_of 01-promote)"
  proof analyze-kill-two-cell KILL "$(verdict_of 02-kill2)"
  proof analyze-kill-pending KILL-PENDING "$(verdict_of 03-kill1)"
  proof analyze-kill-confirmed KILL "$(verdict_of 04-kill1c)"
  proof analyze-kill-unconfirmed INCONCLUSIVE "$(verdict_of 05-kill1u)"
  proof analyze-guard-not-killed INCONCLUSIVE "$(verdict_of 06-guard)"
  proof analyze-unstable INCONCLUSIVE "$(verdict_of 07-unstable)"
  proof analyze-inside INCONCLUSIVE "$(verdict_of 08-inside)"
  proof analyze-malformed INCONCLUSIVE-FINDING "$(verdict_of 09-malformed)"
  python3 "$KIT/analyze.py" --out "$D/out" --plan "$D/plan-dry.tsv" > "$D/table.txt" 2>&1
  proof pooled-median "1.0%" "$(grep '^POOL d4-prose' "$D/table.txt" | awk '{print $3}')"
  proof pooled-pairs 9 "$(grep '^POOL d4-prose' "$D/table.txt" | awk '{print $NF}')"
  proof warmup-not-scored 0 "$(grep -c '^warmup' "$D/out/scores.tsv" || true)"
  proof scored-arms 9 "$(grep -c '^| [0-9]' "$D/table.txt" || true)"

  # 6. The rule against the repo's own receipt: S0 PROMOTE, G8 and C20 INCONCLUSIVE.
  python3 "$KIT/sens.py" --out "$D/sens" > "$D/sens.log" 2>&1
  proof sens-rc 0 "$?"
  proof sens-ok 1 "$(grep -c '^SENS-OK' "$D/sens.log")"

  # 8. The coverage gate's passage rule: fail above and below the marker when the launcher cannot carry it.
  local gate=${KS_GATE_SELFTEST:-}
  if [ -z "$gate" ]; then
    for cand in "$KIT/../env/check-env-coverage-selftest.sh" "$BOX/envgate/check-env-coverage-selftest.sh"; do
      if [ -f "$cand" ]; then gate=$cand; break; fi
    done
  fi
  if [ -f "${gate:-/nonexistent}" ]; then
    bash "$gate" > "$D/envgate.log" 2>&1
    proof coverage-selftest-rc 0 "$?"
    proof coverage-selftest 1 "$(grep -c '^SELFTEST-OK' "$D/envgate.log")"
  else
    proof coverage-selftest-present 1 0
  fi

  # 9. The real plan and the installed committed env pass the same gates: the base the window would carry,
  #    and no arm the launcher cannot carry or that equals the base's own value.
  if [ -f "$REF_SRC" ]; then
    mkdir -p "$D/out-real"
    ( OUT=$D/out-real REF=$D/ref-real ENVD=$D/env-real REPO_ENV=$D/no-repo REF_SRC="$REF_SRC" prepare_ref \
      && OUT=$D/out-real REF=$D/ref-real ENVD=$D/env-real base_filter \
      && OUT=$D/out-real ENVD=$D/env-real plan_gate "$KIT/plan.tsv" ) > "$D/real-gates.log" 2>&1
    proof real-base-and-plan 0 "$?"
    proof real-base-line 1 "$(grep -c '^BASE-CARRIED [0-9]* NOT-CARRIED [0-9]*' "$D/out-real/base-filter.txt" || true)"
    echo "REAL $(head -1 "$D/out-real/base-filter.txt" 2>/dev/null)" | tee -a "$D/proofs.txt"
    nc=$(head -1 "$D/out-real/base-filter.txt" 2>/dev/null | sed -n 's/.*NOT-CARRIED \([0-9]*\).*/\1/p')
    proof real-not-carried-positive 1 "$([ "${nc:-0}" -gt 0 ] && echo 1 || echo 0)"
    echo "REAL plan $(grep -c '^PLAN-' "$D/out-real/PASSAGE-REFUSED" 2>/dev/null || true) refusals"
  else
    proof real-env-present 1 0
  fi

  # 10. The starter is disarmed: no GO, no starter process.
  proof disarm-no-go 0 "$([ -e "$BOX/GO" ] && echo 1 || echo 0)"
  proof disarm-no-starter 0 "$(pgrep -f '[K]nobScreen/starter.sh' | wc -l | tr -d ' ')"

  if [ "$DRY_FAIL" = 0 ]; then
    echo "DRY-OK $(grep -c '^DRY ' "$D/proofs.txt")"
    return 0
  fi
  echo "DRY-FAILED $DRY_FAIL"
  return 1
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
  flock -o -w 43200 "$LOCK" env KL_LOCKED=1 KS_BOX="$BOX" KS_OUT="$OUT" KS_HARNESS="$H" \
    KS_REPO_ENV="$REPO_ENV" KS_REF_SRC="$REF_SRC" KS_PASSES="$PASSES" KS_KIT="$KIT" bash "$SELF" run
  echo "driver exit $? $(now)" >> "$OUT/run.log"
  exit 0
fi

date +%s > "$BOX/started"
DEADLINE=$(( $(cat "$BOX/started") + BUDGET_S ))
log "HELD $(now) lock; deadline $(date -Is -d "@$DEADLINE") budget starts here, not at queue time"

# The base, prepared before anything is booted or stopped: the committed env, its sha, its carried subset and
# a plan whose every arm the launcher can carry. A failure here touches neither production nor the lock's boot.
prepare_ref || exit 9
base_filter || exit 9
allow_args || exit 9
if ! plan_gate "$KIT/plan.tsv"; then
  log "PREFLIGHT-ABORT the plan carries an arm the launcher cannot carry (see $OUT/PASSAGE-REFUSED)"
  echo "PREFLIGHT-ABORT plan passage" > "$OUT/RUN-STOP"
  exit 9
fi
for f in "$H/bench_concurrent.py" "$H/ttft.py" "$KIT/analyze.py" "$KIT/check_env.py" "$KIT/basefilter.py" \
         "$KIT/mkenv.py" "$KIT/rec.py" "$KIT/result.py" "$KIT/stub_cells.py" "$RECIPE/start.sh" "$RECIPE/stop.sh"; do
  [ -f "$f" ] || { log "PREFLIGHT-ABORT missing $f"; echo "PREFLIGHT-ABORT $f" > "$OUT/RUN-STOP"; exit 9; }
done
docker image inspect "$DEV_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $DEV_IMAGE absent"; echo "PREFLIGHT-ABORT dev image" > "$OUT/RUN-STOP"; exit 9; }
[ "$(docker image inspect "$DEV_IMAGE" --format '{{.Id}}')" = "$DEV_IMAGE_ID" ] \
  || { log "PREFLIGHT-ABORT dev image id $(docker image inspect "$DEV_IMAGE" --format '{{.Id}}')"; echo "PREFLIGHT-ABORT dev image id" > "$OUT/RUN-STOP"; exit 9; }
docker image inspect "$PROD_IMAGE" > /dev/null 2>&1 || { log "PREFLIGHT-ABORT $PROD_IMAGE absent"; echo "PREFLIGHT-ABORT prod image" > "$OUT/RUN-STOP"; exit 9; }
log "LAUNCHER $RECIPE/start.sh sha $(sha256sum "$RECIPE/start.sh" | cut -d' ' -f1) config.sh sha $(sha256sum "$RECIPE/scripts/config.sh" 2>/dev/null | cut -d' ' -f1)"

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

warmup || exit 6

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
done < "$KIT/plan.tsv"

python3 "$KIT/analyze.py" --out "$OUT" --plan "$KIT/plan.tsv" > "$OUT/table.md" 2>&1 || true
python3 "$KIT/result.py" --box "$BOX" >> "$OUT/run.log" 2>&1 || true
touch "$OUT/RUN-DONE"
log "DONE $(now)"
