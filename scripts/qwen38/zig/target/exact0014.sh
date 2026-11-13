#!/usr/bin/env bash
# exact0014.sh - upstream CONTRIBUTING's three exactness equalities for the TF_FLASHNEXT_MTP_WEIGHTS pull request:
# drafted == "draft": false, resumed == fresh, concurrent == solo, on main (image um), the branch with the setting
# unset (um14) and the branch with mxfp8 (um14 + TF_FLASHNEXT_MTP_WEIGHTS=mxfp8). Each arm boots twice, fresh:
#   on  (the recipe's prompt cache): tools/bench_concurrent.py --alone --serial on code and chat (temperatures 1.0 and 0,
#       1/2/4 identical streams, 256 tokens, 3 reps) and on the six golden prompts (--prompts, greedy, 1/2/4/6 streams);
#       served_exactness.py drafts (8 prompts, token ids) and turns (a prompt, then the chat extended, resumed);
#       tools/bench_cache.py (repeated and concurrent requests against the first)
#   off (--prompt-cache-gib 0): served_exactness.py fresh (the extended chats, each against its resumed reply), drafts
#       again, zig/tests/qwen35/serve_check.py URL MODEL 256 (its resumed == fresh line is not a resume on this server)
# NVFP4 checkpoint, bf16 KV, 131,072 window, --parallel 4, HOST 127.0.0.1 PORT 8080, MEM_CHECK=0, as receipt0014.sh.
# GPU lock held throughout; production restored on every exit. Needs ~/work/target/up-tools (upstream tools/ at the
# PR's base) and ~/work/target/exact/ (served_exactness.py, serve_check.py, exact0014_sum.py, the three input files).
set -u
cd ~/work/target || exit 1
exec 9>~/work/gpu.lock
flock -w 3600 9 || { echo "exact0014: the GPU lock is held"; exit 1; }
OUT=bench/exact0014; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
URL=http://127.0.0.1:8080
X=exact
MODEL=
log() { echo "$*" >> "$LOG"; }
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/prod.out" 2>&1
  log "RESTORE prod /health $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health) $(date -Is)"
  touch "$OUT/DONE"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
log "START $(date -Is) base $(cat up-tools/BASE_SHA) serve_check.py sha256 $(sha256sum $X/serve_check.py | cut -c1-16)"
for im in um um14; do log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"; done
log "PATCH rungs127/pr0014.patch numstat: $(git apply --numstat rungs127/pr0014.patch 2>&1 | tr '\t\n' ' ;')"
boot() { # dir image on|off [env...]
  local d=$1 img=$2 cache=$3; shift 3
  local extra=(); [ "$cache" = off ] && extra=(--prompt-cache-gib 0)
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart "${extra[@]}" </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' ')"
  log "ENV $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | tr '\n' ' ')"
  log "ARGS $(docker inspect -f '{{join .Args " "}}' qwen38-flash-next-tf 2>/dev/null | cut -c1-400)"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  [ -n "$MODEL" ]
}
down() { # dir
  docker logs qwen38-flash-next-tf > "$1/server.log" 2>&1
  grep -a -m2 'MTP_WEIGHTS\|re-coded\|kept as' "$1/server.log" | cut -c1-160 | sed 's/^/LOG /' >> "$LOG"
  grep -a -m1 'streams at once' "$1/server.log" | cut -c1-420 | sed 's/^/LOG /' >> "$LOG"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
run() { # dir name command...
  local d=$1 name=$2; shift 2
  "$@" > "$d/$name.out" 2>&1
  log "RC $d $name $? $(date -Is)"
}
arm() { # name image [env...]
  local name=$1 img=$2; shift 2
  local d=$OUT/$name
  if boot "$d/on" "$img" on "$@"; then
    run "$d/on" concurrent python3 up-tools/bench_concurrent.py $URL "$MODEL" --tokens 256 --reps 3 \
        --temperatures 1.0,0 --levels 1,2,4 --alone --serial --label "$name" --output "$d/on/concurrent.json"
    run "$d/on" golden python3 up-tools/bench_concurrent.py $URL "$MODEL" --tokens 256 --reps 1 --temperatures 0 \
        --levels 1,2,4,6 --prompts $X/golden.json --alone --serial --label "$name-golden" --output "$d/on/golden.json"
    run "$d/on" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/on/drafts.json"
    run "$d/on" turns python3 $X/served_exactness.py turns $URL "$MODEL" $X/turns.json "$d/on/turns.json"
    run "$d/on" cache python3 up-tools/bench_cache.py $URL "$MODEL" --tokens 256 --repeats 2 --streams 2 \
        --output "$d/on/cache.json"
  fi
  down "$d/on"
  if boot "$d/off" "$img" off "$@"; then
    run "$d/off" fresh python3 $X/served_exactness.py fresh $URL "$MODEL" "$d/on/turns.json" "$d/off/fresh.json"
    run "$d/off" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/off/drafts.json"
    run "$d/off" serve_check python3 $X/serve_check.py $URL "$MODEL" 256
  fi
  down "$d/off"
}
arm main um
arm pr-default um14
arm pr-mxfp8 um14 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
python3 $X/exact0014_sum.py "$OUT" > "$OUT/summary.md" 2>&1
log "SUMMARY rc $? $(date -Is)"
