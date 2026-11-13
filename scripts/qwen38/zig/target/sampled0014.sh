#!/usr/bin/env bash
# sampled0014.sh - the speed half of the TF_FLASHNEXT_MTP_WEIGHTS pull request's last checklist line: sampled decode
# (temperature 1.0), and the drafter on against "draft": false at temperatures 1.0 and 0, on main (image um), the
# branch with the setting unset (um14), the branch with mxfp8 (um14 + TF_FLASHNEXT_MTP_WEIGHTS=mxfp8) and main again
# (um), one fresh boot an arm, in that order. Each boot runs upstream's clients from the PR's base (up-tools/):
#   bench_openai.py at temperature 1.0, 256 tokens, 3 reps (one stream)
#   bench_concurrent.py --alone --serial, code and chat, 1/2/4 streams, 256 tokens, 3 reps, in the order drafter on
#     at 1.0, drafter off at 1.0, drafter off at 0, drafter on at 0 (a drift inside the boot lands on both sides);
#     drafter off is bench_nodraft.py, the same client with "draft": false on every request
#   served_exactness.py drafts at 64 tokens: the server's own drafted count for "draft": false requests (must be 0)
# NVFP4 checkpoint, bf16 KV, 131,072 window, --parallel 4, HOST 127.0.0.1 PORT 8080, MEM_CHECK=0, as receipt0014.sh.
# flock -o holds ~/work/gpu.lock for the whole run (no child keeps it); production is restored on every exit.
# Tables: sampled0014_sum.py. Needs up-tools/ and exact/ (served_exactness.py, prompts.json) beside this script.
set -u
SELF=$(readlink -f "$0")
cd ~/work/target || exit 1
if [ "${SAMPLED_LOCKED:-}" != 1 ]; then
  mkdir -p bench
  flock -o -w 7200 ~/work/gpu.lock env SAMPLED_LOCKED=1 bash "$SELF"
  echo "sampled0014 exit $? $(date -Is)" >> bench/sampled0014.exit
  exit
fi
OUT=bench/sampled0014; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
URL=http://127.0.0.1:8080
UP=up-tools
MODEL=
log() { echo "$*" >> "$LOG"; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' '; }
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/prod.out" 2>&1
  log "RESTORE prod /health $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health) $(date -Is)"
  touch "$OUT/DONE"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
log "START $(date -Is) base $(cat $UP/BASE_SHA)"
for f in $UP/bench_concurrent.py $UP/bench_openai.py bench_nodraft.py exact/served_exactness.py "$SELF"; do
  log "SHA256 $(sha256sum "$f" | cut -c1-16) $f"
done
for im in um um14; do log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"; done
boot() { # dir image [env...]
  local d=$1 img=$2; shift 2
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(gpu)"
  log "ENV $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort | tr '\n' ' ')"
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
  log "RC $d $name $? $(date -Is) gpu $(gpu)"
}
arm() { # name image [env...]
  local name=$1 img=$2; shift 2
  local d=$OUT/$name
  local c=(--tokens 256 --reps 3 --levels 1,2,4 --alone --serial)
  if boot "$d" "$img" "$@"; then
    run "$d" decode_t1 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 3 --temperatures 1.0 \
        --label "$name" --output "$d/decode_t1.json"
    run "$d" on_t1 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 1.0 --label "$name-on" \
        --output "$d/on_t1.json"
    run "$d" off_t1 python3 bench_nodraft.py $URL "$MODEL" "${c[@]}" --temperatures 1.0 --label "$name-off" \
        --output "$d/off_t1.json"
    run "$d" off_t0 python3 bench_nodraft.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label "$name-off" \
        --output "$d/off_t0.json"
    run "$d" on_t0 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label "$name-on" \
        --output "$d/on_t0.json"
    run "$d" drafts python3 exact/served_exactness.py drafts $URL "$MODEL" exact/prompts.json "$d/drafts.json" --tokens 64
  fi
  down "$d"
}
arm main um
arm pr-default um14
arm pr-mxfp8 um14 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
arm main-again um
python3 sampled0014_sum.py "$OUT" "$OUT/summary.md" >> "$LOG" 2>&1
log "SUMMARY rc $? $(date -Is)"
