#!/usr/bin/env bash
# window.sh - why the two engines return different greedy replies: the localisation window, one hold of
# ~/work/gpu.lock on spark6.
#
# WHAT IS MEASURED, and against what
#   P  production: ~/qwen6-start-prod.sh (recipe ~/qwen-zig-prod), image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
#      (sha256:235211ea77ee...), its own 54-name environment, the azampatti INT4-AutoRound checkpoint.
#   D  the dev composition: ~/qwen6-start.sh (recipe ~/qwen-zig) with dev.env, image tensorfold-qwen38:r5dev40
#      (sha256:adc40fe3ea7b...), the same checkpoint.
#   One boot a cell (a serve's concurrency is fixed at boot). Cells: five fixed prompts (prompts/, byte-identical on
#   both arms), greedy (temperature 0, seed 1234, thinking off), 512 tokens, at C=1 and C=8.
#     prose-rec0 / code-rec0  the ParityAB window's own pass-0 requests, byte for byte, so this window's reply shas
#                             can be checked against the recorded ones (reproduction control)
#     prose-1k / code-1k / prose-8k  the localisation prompts (about 1k, 1k and 8k prompt tokens)
#
# CELLS
#   1. P_a, D_a (C=1): the controls. Their divergence at the first token is the spec for stage 2.
#   2. P_b, D_b (C=1): the second boot of each arm (determinism), and the holders of the distribution probes
#      (temperature-1 seed sweep at the forced prefix of every divergent prompt).
#   3. P_a, P_b, D_a, D_b (C=8): determinism and divergence at the widest level.
#   4. The ranked arms, one boot each at C=1, controls interleaved: DRAFTS=0 on both arms, P PROMPT_MM=0,
#      D CHUNK=2048, KV_DTYPE=bf16 on both, D LEARN=0, P VISION=0, INT4_TILE=64 on both (HEAD_ROW_TILES is pinned by
#      both launchers and cannot be moved from the environment), D MTP_WEIGHTS=bf16.
#   5. C=8 for the two drafter arms and the chunk arm.
#
# STAGE 2 (the distribution). Neither engine serves logprobs for this family (prod refuses in the server's field
# parser, the dev Flash Next backend registers no first_row), so the candidate distribution is measured with the API's
# own sampler: the chat prompt ids followed by the reply's ids up to the first divergent token, sent as a token-id
# prompt on /v1/completions with max_tokens 1 and temperature 1, top_k 20, top_p 1, one distinct seed a sample. The
# temperature-0 control at the same prefix must reproduce the arm's own next token; if it does not, the numbers are
# void and the row says so.
#
# RESTORE
#   The EXIT trap stops whichever arm runs, starts production from its own launcher, waits for /health 200, and runs
#   check-prod-env.py against a fresh docker inspect. The outer wrapper re-checks /health after the child exits and
#   restores again under the lock if it is not 200.
#
# RESUMABLE: a cell whose rows.jsonl exists is skipped, so a re-run continues where a failure stopped it.
#
# MARKERS: LOCKED, PREFLIGHT, PROMPTIDS, LOGPROBS, BOOT, IDENTITY, PLAN, PROBE, DIST, CELL-DONE, CELL-FAILED,
# BOOT-FAILED, SKIP, TABLES, DISTSUM, RESTORE, RESTORED, EXIT-DONE.
set -u
SELF=$(readlink -f "$0")
BOX=$HOME/work/parityid
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
MODEL=Qwen3.8-Flash-Next
SEEDS=${SEEDS:-150}
START_EPOCH=""
EXITING=0

if [ "${PID_LOCKED:-}" != 1 ]; then
  mkdir -p "$OUT"
  LOG=$OUT/run.log
  echo "$(date -Is) queued for ~/work/gpu.lock (holders: $(pgrep -af '[f]lock .*gpu\.lock' | tr '\n' ' '))" >> "$LOG"
  flock -o -w 43200 "$HOME/work/gpu.lock" env PID_LOCKED=1 LOG="$LOG" bash "$SELF"
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
recipe_of() { if [ "$1" = P ]; then echo "$P_RECIPE"; else echo "$D_RECIPE"; fi; }
tag_of() { if [ "$1" = P ]; then echo "$P_TAG"; else echo "$D_TAG"; fi; }
id_of() { if [ "$1" = P ]; then echo "$P_ID"; else echo "$D_ID"; fi; }

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

# ---------------- phase 0: preflight (production still serving) ----------------
preflight() {
  mkdir -p "$OUT/phase0"
  local arm
  for arm in P D; do
    docker image inspect "$(tag_of "$arm")" > "$OUT/phase0/img-$arm.json" 2>&1 || true
    log "PREFLIGHT image $arm $(docker image inspect -f '{{.Id}}' "$(tag_of "$arm")" 2>/dev/null) expected $(id_of "$arm")"
  done
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$OUT/phase0/live-image.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$OUT/phase0/live-cmd.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$OUT/phase0/live-env.txt" || true
  curl -s --max-time 10 "$URL/health" > "$OUT/phase0/live-health.json" 2>/dev/null || true
  log "PREFLIGHT live $(cat "$OUT/phase0/live-image.txt" 2>/dev/null) health $(healthcode) env_names $(wc -l < "$OUT/phase0/live-env.txt") gpu $(gpu) mem_avail $(memavail)"

  # The prompt ids each arm renders for the five prompts (the model's actual input), and the logprobs refusal.
  python3 - "$IN/prompts" "$OUT/phase0/promptids-live.txt" <<'PY' >> "$LOG" 2>&1 || true
import json, os, sys, urllib.request
d, out = sys.argv[1], sys.argv[2]
rows = []
for name in ("prose-rec0", "code-rec0", "prose-1k", "code-1k", "prose-8k"):
    text = open(os.path.join(d, name + ".txt"), encoding="utf-8").read()
    body = {"messages": [{"role": "user", "content": text}],
            "chat_template_kwargs": {"enable_thinking": False}, "add_generation_prompt": True}
    req = urllib.request.Request("http://127.0.0.1:8888/tokenize", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    try:
        ids = json.loads(urllib.request.urlopen(req, timeout=60).read().decode()).get("tokens") or []
        rows.append({"prompt": name, "count": len(ids), "first": ids[:8], "last": ids[-8:]})
    except Exception as e:
        rows.append({"prompt": name, "error": repr(e)})
open(out, "w").write(json.dumps(rows, indent=1))
for r in rows:
    print("PROMPTIDS live", r.get("prompt"), r.get("count"), r.get("error", ""))
PY
  [ -s "$OUT/phase0/promptids-live.txt" ] && log "PROMPTIDS live ids captured in phase0/promptids-live.txt"
}

# ---------------- boot, capture, probes ----------------
probe_logprobs() { # dir
  local d=$1 code
  code=$(curl -s -o "$d/logprobs-chat.json" -w '%{http_code}' --max-time 60 -X POST "$URL/v1/chat/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":1,\"logprobs\":true,\"top_logprobs\":5}" 2>/dev/null || true)
  echo "chat $code $(head -c 300 "$d/logprobs-chat.json" 2>/dev/null)" > "$d/logprobs.txt"
  code=$(curl -s -o "$d/logprobs-comp.json" -w '%{http_code}' --max-time 60 -X POST "$URL/v1/completions" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"$MODEL\",\"prompt\":\"hi\",\"max_tokens\":1,\"logprobs\":5}" 2>/dev/null || true)
  echo "completions $code $(head -c 300 "$d/logprobs-comp.json" 2>/dev/null)" >> "$d/logprobs.txt"
  log "LOGPROBS $(head -1 "$d/logprobs.txt" | cut -c1-160)"
}

capture() { # arm C dir
  local arm=$1 C=$2 d=$3 img
  docker inspect "$CN" --format '{{.Config.Image}} {{.Image}}' > "$d/image-id.txt" 2>/dev/null || true
  docker inspect "$CN" --format '{{json .Config.Cmd}}' > "$d/cmd.json" 2>/dev/null || true
  docker inspect "$CN" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
    | grep -E '^(TF_|TENSORFOLD_)' | sort > "$d/env.txt" || true
  curl -s --max-time 10 "$URL/health" > "$d/health.json" 2>/dev/null || true
  docker logs "$CN" > "$d/boot.log" 2>&1 || true
  {
    grep -a -m1 -o '[0-9]* streams at once,.*' "$d/boot.log"
    grep -a -m1 -o 'prompt chunks of up to .*' "$d/boot.log"
    grep -a -m1 -o 'prompt passes of .*' "$d/boot.log"
    grep -a -m1 -o 'prompt path: .*' "$d/boot.log"
    grep -a -m1 -o 'matmul K slices.*' "$d/boot.log"
    grep -a -m1 -o 'int4 kernels: .*' "$d/boot.log"
    grep -a -m1 -o 'int4 prompt gate/up: .*' "$d/boot.log"
    grep -a -m1 -o 'int4 lm_head: .*' "$d/boot.log"
    grep -a -m1 -o 'drafts: .*' "$d/boot.log"
    grep -a -m1 -o 'draft stop: .*' "$d/boot.log"
    grep -a -m1 -o "the drafter's BF16 linears kept as .*" "$d/boot.log"
    grep -a -m1 -o 'overlay .*mtp-fp8.*' "$d/boot.log"
    grep -a -m1 -o 'qsa select: .*' "$d/boot.log"
    grep -a -m1 -o 'copy policy: .*' "$d/boot.log"
    grep -a -m1 -o 'block-FP8 split-K shapes.*' "$d/boot.log"
    grep -a -m1 -o 'block-FP8 prompt tiles.*' "$d/boot.log"
    grep -a -m1 -o 'KV page groups: .*' "$d/boot.log"
    grep -a -m1 -o 'sequence memory: .*' "$d/boot.log"
    grep -a -m1 -o 'graph warm-up: .*' "$d/boot.log"
    grep -a -m1 -o 'graphs: .*' "$d/boot.log"
    grep -a -m1 -o 'vision: .*' "$d/boot.log"
    grep -a -m1 -o 'conversation states on disk .*' "$d/boot.log"
    grep -a -m1 -o 'prompt cache: .*' "$d/boot.log"
  } > "$d/plan.txt" 2>/dev/null
  img=$(cat "$d/image-id.txt" 2>/dev/null)
  case "$img" in
    *"$(tag_of "$arm") $(id_of "$arm")"*) log "IDENTITY $arm c$C OK $img" ;;
    *) log "IDENTITY $arm c$C WRONG ${img:-absent} expected $(tag_of "$arm") $(id_of "$arm")" ;;
  esac
  while IFS= read -r line; do [ -n "$line" ] && log "PLAN $arm c$C $line"; done < "$d/plan.txt"
}

cell() { # label mode C dist
  local label=$1 mode=$2 C=$3 dist=$4 arm=${1%%_*} d=$OUT/$1/c$3 rc=0 t0 t1 code
  if [ -s "$d/rows.jsonl" ]; then log "SKIP $label c$C (rows.jsonl present, $(wc -l < "$d/rows.jsonl") lines)"; return 0; fi
  mkdir -p "$d"
  if [ "$arm" = D ]; then clear_dstore; fi
  wait_resources || { log "RESOURCES-LOW $label c$C"; }
  echo "boot_start $(gpu)" > "$d/gpu.txt"
  t0=$(date +%s.%N)
  "$IN/boot_cell.sh" "$arm" "$mode" "$C" 0 > "$d/launch.log" 2>&1 || rc=$?
  t1=$(date +%s.%N)
  awk -v a="$t0" -v b="$t1" 'BEGIN{printf "boot_s %.1f\n", b-a}' > "$d/boot_time.txt"
  echo "boot_rc $rc" >> "$d/boot_time.txt"
  code=$(healthcode)
  log "BOOT $label c$C rc $rc health $code $(tr '\n' ' ' < "$d/boot_time.txt") gpu $(gpu) mem_avail $(memavail)"
  if [ "$rc" != 0 ] || [ "$code" != 200 ]; then
    log "BOOT-FAILED $label c$C :: $(tail -4 "$d/launch.log" | tr '\n' ' ')"
    grep -a -m2 -o 'memory available;.*\|refus.*\|error[^ ]*.*' "$d/launch.log" >> "$d/refusal.txt" 2>/dev/null || true
    stop_serve "$(recipe_of "$arm")"
    return 1
  fi
  docker logs "$CN" > "$d/boot.log" 2>&1 || true
  : > "$d/plan.txt"
  capture "$arm" "$C" "$d"
  probe_logprobs "$d"
  python3 "$IN/parity_probe.py" "$label" "$arm" "$mode" "$C" "$d/rows.jsonl" > "$d/probe.log" 2>&1 || rc=$?
  log "PROBE $label c$C greedy rc $rc rows $(cat "$d/rows.jsonl" 2>/dev/null | wc -l)"
  if [ "$dist" = 1 ] && [ -s "$OUT/dist/spec-c1.json" ]; then
    python3 "$IN/dist_probe.py" "$OUT/dist/spec-c1.json" "$arm" "$OUT/dist/$label-c$C.jsonl" "$SEEDS" \
      > "$d/dist.log" 2>&1 || rc=$?
    log "DIST $label c$C rc $rc rows $(wc -l < "$OUT/dist/$label-c$C.jsonl" 2>/dev/null)"
  fi
  stop_serve "$(recipe_of "$arm")"
  log "CELL-DONE $label c$C rc $rc elapsed $(elapsed_min) min"
  return $rc
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
log "PAYLOAD $(cd "$IN" && sha256sum *.py *.sh dev.env prod.env prompts/*.txt 2>/dev/null | tr '\n' ' ')"
log "GPU start $(gpu) mem_avail $(memavail) disk $(diskfree) health $(healthcode)"

preflight
stop_serve "$P_RECIPE"
log "STOPPED production for the matrix $(date -Is) health $(healthcode) mem_avail $(memavail)"

# 1. the C=1 controls, then the spec, then the second boots with the distribution probes
cell P_a control 1 0
cell D_a control 1 0
mkdir -p "$OUT/dist"
python3 "$IN/analyse.py" spec --root "$OUT" --pair P_a:D_a --c 1 --out "$OUT/dist/spec-c1.json" >> "$LOG" 2>&1 || true
log "SPEC $(python3 -c 'import json,sys; s=json.load(open(sys.argv[1])); print(len(s["cells"]), "cells", [c["name"] for c in s["cells"]])' "$OUT/dist/spec-c1.json" 2>/dev/null)"
cell P_b control 1 1
cell D_b control 1 1
python3 "$IN/analyse.py" report --root "$OUT" --md "$OUT/report1.md" --json "$OUT/report1.json" >> "$LOG" 2>&1 || true
log "REPORT1 $(grep -c '^|' "$OUT/report1.md" 2>/dev/null) table rows"

# 2. the C=8 controls
cell P_a control 8 0
cell D_a control 8 0
cell P_b control 8 0
cell D_b control 8 0
python3 "$IN/analyse.py" report --root "$OUT" --md "$OUT/report2.md" --json "$OUT/report2.json" >> "$LOG" 2>&1 || true
log "REPORT2 C=8 $(grep -c '^|' "$OUT/report2.md" 2>/dev/null) table rows"

# 3. the ranked arms at C=1 (controls interleaved)
cell P_nodrafts nodrafts 1 0
cell D_nodrafts nodrafts 1 0
cell P_pmm0 pmm0 1 0
cell D_chunk2048 chunk2048 1 0
cell P_bf16kv bf16kv 1 0
cell D_bf16kv bf16kv 1 0
cell D_notier notier 1 0
cell P_novision novision 1 0
cell D_int4tile64 int4tile64 1 0
cell P_int4tile64 int4tile64 1 0
cell D_mtpbf16 mtpbf16 1 0
python3 "$IN/analyse.py" report --root "$OUT" --md "$OUT/report3.md" --json "$OUT/report3.json" >> "$LOG" 2>&1 || true
log "REPORT3 $(grep -c '^|' "$OUT/report3.md" 2>/dev/null) table rows"

# 4. C=8 for the drafter arms and the chunk arm
cell P_nodrafts nodrafts 8 0
cell D_nodrafts nodrafts 8 0
cell D_chunk2048 chunk2048 8 0

python3 "$IN/analyse.py" report --root "$OUT" --md "$OUT/tables.md" --json "$OUT/tables.json" >> "$LOG" 2>&1 || true
python3 "$IN/analyse.py" distsum --root "$OUT" --md "$OUT/dist.md" >> "$LOG" 2>&1 || true
log "TABLES $(wc -l < "$OUT/tables.md" 2>/dev/null) lines; DISTSUM $(wc -l < "$OUT/dist.md" 2>/dev/null) lines"
log "CELLS $(grep -c 'CELL-DONE' "$LOG") done, $(grep -c 'CELL-FAILED' "$LOG") failed, $(grep -c 'BOOT-FAILED' "$LOG") boot-failed"
log "RUN-DONE $(date -Is) elapsed $(elapsed_min) min"
