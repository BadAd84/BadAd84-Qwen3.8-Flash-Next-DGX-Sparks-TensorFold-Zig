#!/usr/bin/env bash
# window.sh - r5dev40 against production, interleaved, one hold of ~/work/gpu.lock on spark6.
#
# WHAT IS MEASURED, and against what
#   P  production: its own launcher (~/qwen6-start-prod.sh, recipe ~/qwen-zig-prod), image
#      tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 (sha256:235211ea77ee...), its 54-name environment,
#      the azampatti INT4-AutoRound checkpoint, 262,144-token window, fp8 KV, vision on, warm turns off.
#   D  the dev composition: ~/qwen6-start.sh (recipe ~/qwen-zig) with dev.env sourced, image
#      tensorfold-qwen38:r5dev40 (sha256:adc40fe3ea7b...), CHECKPOINT=int4 (the SAME azampatti INT4-AutoRound
#      checkpoint), VISION=0, KV_DTYPE=fp8, TF_FLASHNEXT_MTP_WEIGHTS=mxfp8, the persistent KV tier
#      (--prompt-cache-gib 6 --prompt-cache-disk /cache/kv --learn-gib 60 ...), 262,144-token window, warm turns off.
#   Both arms boot at PARALLEL=C on loopback, one FRESH BOOT A LEVEL, in an interleaved order that alternates which
#   arm boots first, exactly the shape the target's own cells were measured in (PARALLEL=C, fresh boot a level).
#   The checkpoint is the same on both arms; the engine and the environment are what differ.
#
# PREFLIGHT, before any cell (phase 0, production still live for the identity capture)
#   image ids against the pins; the live production identity (container image, command, model directory, env, health);
#   every TF_/TENSORFOLD_ name each arm sets, checked against the served binary's own strings (the binary is the
#   oracle); each arm's DRY_RUN launcher (which also runs the recipe's own full-argv argument check) parsed for its
#   exact flag list, and every flag put through the served binary's parser with a deliberately incomplete command
#   line (FLAG-SUMMARY); the dry run's flag names compared with the live production command's. Each boot then
#   re-captures its instantiated command, and flags or env names it carries that the preflight did not test are
#   tested at that boot (FLAGS-EXTRA / ENVRECON); nothing measured is left untested.
#
# CELLS
#   golden 6/6 (qf_harness golden against the stock reference), then decode: C barrier-started greedy requests,
#   512 tokens, distinct prompts with a per-pass nonce, thinking off, prose then code, 3 passes, the engine's own
#   token hash recorded for every reply (tfm_decode_ids.py = the target's tfm_decode.py plus token hashes), then
#   TTFT: cold 1k (the instrument control), 8k and 32k, thinking off and on, idle, 2 reps, and the warm agent turn
#   (a kept 100k conversation plus 2k new tokens) with the cached-token counts the harness prints and flags on.
#
# DECLARED REPEATS AND THE RERUN RULE (declared before the first cell exists; score_cells.py is the only judge)
#   Repeats: decode = 3 passes a cell, the median reported (the target's own repeat); TTFT = 2 reps a case, the
#   median (the target's own repeat); warm = 2 reps, both must show cached tokens at or above half the prompt or
#   the harness flags them and they do not count.
#   R1  a decode cell whose three passes span more than 5% (max/min - 1) is re-measured;
#   R2  a cell with a failed pass or fewer than three passes is re-measured;
#   R3  a cell pair within 1% of each other is re-measured on BOTH arms (a tie is resolved by a second boot);
#   R4  a TTFT case with fewer than two unflagged samples, an excluded sample, or more than 10% spread is re-measured;
#   R5  the warm case with no cached-token evidence is re-measured.
#   One rerun pass only: the tripped level is re-booted for BOTH arms in reverse order (the pair must stay adjacent),
#   and a cell still tripping after that is reported with its spread, marked noisy, not re-run again.
#
# THE PERSISTENT TIER AND COLDNESS (a declared deviation of method, needed for a like-for-like cell)
#   D's tier keeps prompt states on disk across boots; the decode prompts repeat across boots by design (so the two
#   arms can be compared at identical prompts). The tier's store is therefore emptied before every D boot, inside a
#   throwaway container (the directory is root-owned): every decode prompt is cold in every boot, as it is on the
#   target's per-process cache. The warm cell is unaffected - it primes its own conversation inside the boot.
#
# RESTORE
#   The EXIT trap stops whichever arm runs, starts production from its own launcher with the pinned image, waits for
#   /health 200, and runs check-prod-env.py against a fresh docker inspect (EQUAL expected). The outer wrapper
#   re-checks /health after the child exits and restores again under the lock if it is not 200.
#
# MARKERS (what the report greps): LOCKED, PREFLIGHT, ENVSTR, FLAG, FLAGS-BOOT, MODEL-MATCH, BOOT, IDENTITY,
# PLAN, CACHE-CLEAR, PROBE, CELL-DONE, CELL-FAILED, BOOT-FAILED, SCORE1, RERUN, SCORE2, RUN-DONE, RESTORE,
# RESTORED, EXIT-DONE.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/parity
IN=$BOX/in
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
LEVELS=(1 2 4 6 8)
declare -A ORD1=([1]="P D" [2]="D P" [4]="P D" [6]="D P" [8]="P D")
declare -A ORD2=([1]="D P" [2]="P D" [4]="D P" [6]="P D" [8]="D P")
EXCLUDE=TF_REF,TF_REPO,TF_TAG,TF_RELEASE,TF_RELEASE_VERSION,TF_RELEASE_AARCH64_SHA256
START_EPOCH=""
EXITING=0

if [ "${PARITY_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env PARITY_LOCKED=1 LOG="$LOG" bash "$SELF"
  rc=$?
  echo "window.sh exit $rc $(date -Is)" >> "$LOG"
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
tag_of() { if [ "$1" = P ]; then echo "$P_TAG"; else echo "$D_TAG"; fi; }
id_of() { if [ "$1" = P ]; then echo "$P_ID"; else echo "$D_ID"; fi; }
recipe_of() { if [ "$1" = P ]; then echo "$P_RECIPE"; else echo "$D_RECIPE"; fi; }

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
  # The recipe's own pre-boot guard needs ~91-93 GiB MemAvailable for a 262,144-token window and dies otherwise
  # (measured: "a 262144-token window needs ~93"); wait for just above it, then let the boot's own guard decide.
  local i
  for i in $(seq 1 90); do
    [ "$(memavail)" -ge 92 ] && [ "$(diskfree)" -ge 25 ] && return 0
    sleep 10
  done
  log "RESOURCES-TIMEOUT mem_avail $(memavail) disk $(diskfree); trying the boot anyway (its own guard decides)"
  return 0
}
# The tier's prompt states, emptied from inside a throwaway container (the store is root-owned on the host).
clear_dstore() {
  docker run --rm -v "$CACHE_DIR":/cache --entrypoint sh "$D_TAG" -c \
    'printf "before kv=%s kvtier=%s\n" "$(du -sh /cache/kv 2>/dev/null | cut -f1)" "$(du -sh /cache/kvtier 2>/dev/null | cut -f1)"; rm -rf /cache/kv /cache/kvtier; echo cleared' \
    >> "$LOG" 2>&1 || log "CACHE-CLEAR failed"
}

# The binary is the oracle for the setting names it knows (PROMOTION-RULES): a name is carried when the served
# binary contains it as a token. `tr`-and-exact-line misses names stored inside a longer printable run (measured:
# TENSORFOLD_CUDA_KERNELS, 4 occurrences in the dev binary, 0 exact-line hits), so the extraction is a token scan.
strings_scan() { # image outfile
  docker run --rm --network none --entrypoint sh "$1" -c \
    "grep -a -o -E '(TF|TENSORFOLD)_[A-Z0-9_]+' /opt/tensorfold/native/bin/tensorfold-native | sort -u" \
    > "$2" 2>&1 || true
}

# ---------------- phase 0: preflight ----------------
preflight() {
  local arm
  mkdir -p "$OUT/phase0"
  for arm in P D; do
    docker image inspect "$(tag_of "$arm")" > "$OUT/phase0/img-$arm.json" 2>&1 || true
    log "PREFLIGHT image $arm $(docker image inspect -f '{{.Id}}' "$(tag_of "$arm")" 2>/dev/null) expected $(id_of "$arm")"
  done
  curl -s --max-time 10 "$URL/health" > "$OUT/phase0/live-health.json" 2>/dev/null || true
  curl -s --max-time 10 "$URL/v1/models" > "$OUT/phase0/live-models.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/phase0/live-image.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$OUT/phase0/live-cmd.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$OUT/phase0/live-env.txt" || true
  docker ps --format '{{.Names}} {{.Image}} {{.Status}}' > "$OUT/phase0/live-ps.txt" 2>/dev/null || true
  log "PREFLIGHT live $(cat "$OUT/phase0/live-image.txt" 2>/dev/null) health $(healthcode) env_names $(wc -l < "$OUT/phase0/live-env.txt") gpu $(gpu) mem_avail $(memavail) disk $(diskfree)"

  for arm in P D; do
    strings_scan "$(tag_of "$arm")" "$OUT/phase0/strings-$arm.txt"
    log "PREFLIGHT strings $arm $(wc -l < "$OUT/phase0/strings-$arm.txt") setting names carried by the served binary"
  done

  python3 "$IN/envnames.py" from-env --env "$OUT/phase0/live-env.txt" --launcher "$PROD_START" \
    --config "$P_RECIPE/scripts/config.sh" --exclude "$EXCLUDE" --out "$OUT/phase0/names-P.txt" >> "$LOG" 2>&1
  python3 "$IN/envnames.py" list --dev-env "$IN/dev.env" --launcher "$DEV_START" \
    --config "$D_RECIPE/scripts/config.sh" --exclude "$EXCLUDE" --out "$OUT/phase0/names-D.txt" >> "$LOG" 2>&1
  for arm in P D; do
    python3 "$IN/envnames.py" check --names "$OUT/phase0/names-$arm.txt" --strings "$OUT/phase0/strings-$arm.txt" \
      > "$OUT/phase0/envstr-$arm.txt" 2>&1 || true
    log "ENVSTR $arm $(head -1 "$OUT/phase0/envstr-$arm.txt")"
    grep '^ENVSTR-MISSING' "$OUT/phase0/envstr-$arm.txt" | while read -r _ name; do log "ENVSTR-MISSING $arm $name"; done
  done

  for arm in P D; do
    ( "$IN/boot_env.sh" "$arm" 1 1 ) > "$OUT/phase0/dry-$arm.txt" 2>&1 || true
    python3 "$IN/argv.py" line "$OUT/phase0/dry-$arm.txt" > "$OUT/phase0/flags-$arm.txt" 2>&1 || true
    awk -F'\t' '!/^#/{print $1}' "$OUT/phase0/flags-$arm.txt" | sort -u > "$OUT/phase0/flagnames-$arm.txt"
    bash "$IN/flags.sh" "$(tag_of "$arm")" "$OUT/phase0/flags-$arm.txt" "$OUT/phase0/flagcheck-$arm" >> "$LOG" 2>&1 \
      || log "PREFLIGHT FLAGCHECK-FAILED $arm"
    log "PREFLIGHT argv $arm $(grep -m1 '^# flagcount' "$OUT/phase0/flags-$arm.txt") $(grep -m1 '^# model' "$OUT/phase0/flags-$arm.txt")"
    log "PREFLIGHT flags $arm $(grep -m1 '^FLAG-SUMMARY' "$OUT/phase0/flagcheck-$arm/flags.txt") :: $(grep -m1 '^FLAG-FULL' "$OUT/phase0/flagcheck-$arm/flags.txt")"
  done
  python3 "$IN/argv.py" cmd "$OUT/phase0/live-cmd.json" > "$OUT/phase0/flags-live.txt" 2>&1 || true
  awk -F'\t' '!/^#/{print $1}' "$OUT/phase0/flags-live.txt" | sort -u > "$OUT/phase0/flagnames-live.txt"
  if diff -q "$OUT/phase0/flagnames-P.txt" "$OUT/phase0/flagnames-live.txt" >/dev/null 2>&1; then
    echo "SAME $(wc -l < "$OUT/phase0/flagnames-P.txt") flag names as the live production command" > "$OUT/phase0/flagmatch.txt"
  else
    { echo "DIFF (dry run against the live production command)"; \
      diff "$OUT/phase0/flagnames-P.txt" "$OUT/phase0/flagnames-live.txt"; } > "$OUT/phase0/flagmatch.txt" 2>&1
  fi
  log "PREFLIGHT flagmatch $(head -1 "$OUT/phase0/flagmatch.txt")"
  log "PREFLIGHT lock-holders $(pgrep -af '[f]lock .*gpu\.lock' | head -3 | tr '\n' ' ')"
}

# ---------------- boot, capture, probes ----------------
boot_arm() { # arm C dir
  local arm=$1 C=$2 d=$3 rc=0 t0 t1 code
  mkdir -p "$d"
  wait_resources || { log "RESOURCES-LOW $arm c$C mem_avail $(memavail) disk $(diskfree)"; return 1; }
  echo "boot_start $(gpu)" > "$d/gpu.txt"
  t0=$(date +%s.%N)
  "$IN/boot_env.sh" "$arm" "$C" 0 > "$d/boot.log" 2>&1 || rc=$?
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
  local arm=$1 C=$2 d=$3 img untested
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
    grep -a -m1 -o 'vision: .*' "$d/server.log"
    grep -a -m1 -o 'draft head: .*' "$d/server.log"
    grep -a -m1 -o 'int4 kernels: .*' "$d/server.log"
    grep -a -m1 -o '"max_batch_size": [0-9]*' "$d/health.json"
    grep -a -m1 -o '"context": [0-9]*' "$d/health.json"
  } > "$d/plan.txt" 2>/dev/null
  img=$(cat "$d/image-id.txt" 2>/dev/null)
  case "$img" in
    *"$(tag_of "$arm") $(id_of "$arm")"*) log "IDENTITY $arm c$C OK $img" ;;
    *) log "IDENTITY $arm c$C WRONG ${img:-absent} expected $(tag_of "$arm") $(id_of "$arm")" ;;
  esac
  while IFS= read -r line; do [ -n "$line" ] && log "PLAN $arm c$C $line"; done < "$d/plan.txt"
  python3 "$IN/argv.py" cmd "$d/cmd.json" > "$d/flags-boot.txt" 2>&1 || true
  awk -F'\t' '!/^#/{print $1}' "$d/flags-boot.txt" | sort -u > "$d/flagnames-boot.txt"
  untested=$(comm -23 "$d/flagnames-boot.txt" "$OUT/phase0/flagnames-$arm.txt" | tr '\n' ' ')
  if [ -n "${untested// /}" ]; then
    log "FLAGS-BOOT $arm c$C untested at preflight: $untested (testing now)"
    bash "$IN/flags.sh" "$(tag_of "$arm")" "$d/flags-boot.txt" "$d/flagcheck-extra" >> "$LOG" 2>&1 || true
    cp "$OUT/phase0/flagcheck-$arm/flags.txt" "$d/flagcheck.txt" 2>/dev/null
    cat "$d/flagcheck-extra/flags.txt" >> "$d/flagcheck.txt" 2>/dev/null
  else
    log "FLAGS-BOOT $arm c$C $(wc -l < "$d/flagnames-boot.txt") flags, all tested at preflight"
    cp "$OUT/phase0/flagcheck-$arm/flags.txt" "$d/flagcheck.txt" 2>/dev/null
  fi
  cp "$OUT/phase0/envstr-$arm.txt" "$d/envstr.txt" 2>/dev/null
  if [ "$arm" = D ] && [ ! -f "$OUT/phase0/envrecon-D.txt" ]; then
    python3 "$IN/envnames.py" reconcile --names "$OUT/phase0/names-D.txt" --env "$d/env.txt" \
      > "$OUT/phase0/envrecon-D.txt" 2>&1 || true
    log "ENVRECON D $(head -1 "$OUT/phase0/envrecon-D.txt")"
    if grep -q 'ENVRECON-UNTESTED' "$OUT/phase0/envrecon-D.txt"; then
      { cat "$OUT/phase0/names-D.txt"; grep '^ENVRECON-UNTESTED' "$OUT/phase0/envrecon-D.txt" | awk '{print $2}'; } \
        | sort -u > "$OUT/phase0/names-D-all.txt"
      python3 "$IN/envnames.py" check --names "$OUT/phase0/names-D-all.txt" --strings "$OUT/phase0/strings-D.txt" \
        > "$OUT/phase0/envstr-D-all.txt" 2>&1 || true
      log "ENVSTR D-all $(head -1 "$OUT/phase0/envstr-D-all.txt")"
      cp "$OUT/phase0/envstr-D-all.txt" "$d/envstr.txt" 2>/dev/null
    fi
  fi
}

probe() { # dir name command...
  local d=$1 name=$2 rc=0
  shift 2
  echo "$name gpu $(gpu)" >> "$d/gpu.txt"
  "$@" > "$d/$name.out" 2>&1 || rc=$?
  echo "$name gpu_after $(gpu)" >> "$d/gpu.txt"
  log "PROBE $d $name rc $rc gpu $(gpu) mem_avail $(memavail)"
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
  python3 "$IN/meta.py" "$d" "$arm" "$C" >/dev/null 2>&1
  stop_serve "$(recipe_of "$arm")"
  log "CELL-DONE $arm c$C run$run rc $rc elapsed $(elapsed_min) min"
  return $rc
}
shoot() { # arm C runno
  local arm=$1 C=$2 run=$3
  if [ "$arm" = D ]; then clear_dstore; fi
  shot_arm "$arm" "$C" "$run"
}

# ---------------- restore ----------------
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
  python3 "$IN/check-prod-env.py" --prod "$IN/prod.env" --inspect "$OUT/restored/prod-inspect.json" \
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
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

preflight
stop_serve "$P_RECIPE"
log "STOPPED production for the matrix $(date -Is) health $(healthcode) mem_avail $(memavail)"

for C in "${LEVELS[@]}"; do
  for arm in ${ORD1[$C]}; do shoot "$arm" "$C" 1; done
done
python3 "$IN/score_cells.py" --root "$OUT" > "$OUT/score1.txt" 2>&1 || true
log "SCORE1 $(grep -m1 '^SCORE-SUMMARY' "$OUT/score1.txt")"
grep '^RERUN' "$OUT/score1.txt" | awk '{print $3}' | sed 's/^c//' | sort -n | uniq > "$OUT/rerun1.levels" || true
log "RERUN levels[$(tr '\n' ' ' < "$OUT/rerun1.levels")]"
while read -r C; do
  [ -n "${C:-}" ] || continue
  for arm in ${ORD2[$C]}; do shoot "$arm" "$C" 2; done
done < "$OUT/rerun1.levels"
python3 "$IN/score_cells.py" --root "$OUT" --final > "$OUT/score2.txt" 2>&1 || true
log "SCORE2 $(grep -m1 '^SCORE-SUMMARY' "$OUT/score2.txt")"
grep '^RERUN' "$OUT/score2.txt" | while read -r _ arm cc reason; do log "RERUN-OPEN $arm $cc $reason"; done

python3 "$IN/summarise_parity.py" --root "$OUT" > "$OUT/tables.md" 2>&1 || true
log "TABLES $(wc -l < "$OUT/tables.md") lines in $OUT/tables.md"
log "FOREIGN $(for d in "$OUT"/P/c*/run* "$OUT"/D/c*/run*; do [ -d "$d" ] && echo "$(basename "$(dirname "$(dirname "$d")")")/$(basename "$d")=$(sed -n 's/^foreign_lines=//p' "$d/meta.txt" 2>/dev/null)"; done | tr '\n' ' ')"
log "RUN-DONE $(date -Is) elapsed $(elapsed_min) min"
