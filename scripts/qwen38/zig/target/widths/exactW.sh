#!/usr/bin/env bash
# exactW.sh - the self-exactness arms of the widths step on images wm (main) and wb (branch): with the prompt cache on,
# concurrent equals solo (bench_concurrent --alone --serial, greedy and temperature 1.0), drafted equals "draft": false
# and multi-turn replies (served_exactness.py); with it off, a fresh prompt equals the resumed turn's. Then the
# exact0014 summary. Waits for receiptW.sh to finish; GPU lock held; production restored on every exit.
set -u
SELF=$(readlink -f "$0")
while [ ! -f ~/work/widths/receipt/DONE ]; do sleep 30; done
if [ "${EW_LOCKED:-}" != 1 ]; then
  flock -o -w 43200 ~/work/gpu.lock env EW_LOCKED=1 bash "$SELF" "$@"
  exit
fi
OUT=$HOME/work/widths/receipt/exact; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
UP=$HOME/work/widths/tools
X=$HOME/work/target/exact15
URL=http://127.0.0.1:8080
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
boot() { # dir image on|off
  local d=$1 img=$2 cache=$3
  local extra=(); [ "$cache" = off ] && extra=(--prompt-cache-gib 0)
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart "${extra[@]}" </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  [ -n "$MODEL" ]
}
down() { docker logs qwen38-flash-next-tf > "$1/server.log" 2>&1; ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1; }
run() { local d=$1 name=$2; shift 2; "$@" > "$d/$name.out" 2>&1; log "RC $d $name $? $(date -Is)"; }
exact() { # name image
  local d=$OUT/$1
  if boot "$d/on" "$2" on; then
    run "$d/on" concurrent python3 "$UP/bench_concurrent.py" $URL "$MODEL" --tokens 256 --reps 3 \
        --temperatures 1.0,0 --levels 1,2,4 --alone --serial --label "$1" --output "$d/on/concurrent.json"
    run "$d/on" golden python3 "$UP/bench_concurrent.py" $URL "$MODEL" --tokens 256 --reps 1 --temperatures 0 \
        --levels 1,2,4,6 --prompts $X/golden.json --alone --serial --label "$1-golden" --output "$d/on/golden.json"
    run "$d/on" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/on/drafts.json"
    run "$d/on" turns python3 $X/served_exactness.py turns $URL "$MODEL" $X/turns.json "$d/on/turns.json"
  fi
  down "$d/on"
  if boot "$d/off" "$2" off; then
    run "$d/off" fresh python3 $X/served_exactness.py fresh $URL "$MODEL" "$d/on/turns.json" "$d/off/fresh.json"
    run "$d/off" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/off/drafts.json"
  fi
  down "$d/off"
}
exact main wm
exact branch wb
python3 ~/work/target/exact0014_sum.py "$OUT" > "$OUT/summary.md" 2>&1
log "SUMMARY rc $? $(date -Is)"
