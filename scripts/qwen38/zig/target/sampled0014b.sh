#!/usr/bin/env bash
# sampled0014b.sh - more boots for the sampled cells of sampled0014.sh, whose single boot an arm put six PR cells
# 0.7-1.7% below both main boots while the unset arm (main's work token for token) was 0.9-1.5% above them in every
# greedy cell. Six fresh boots in the order main, PR unset, PR mxfp8, PR mxfp8, PR unset, main (a palindrome, so a
# drift over the run falls equally on every arm), after one throwaway pass in the first boot that warms the GPU.
# Each boot: tools/bench_openai.py at temperature 1.0 with 9 seeds (1234-1242), 256 tokens (one stream), then
# tools/bench_concurrent.py --alone --serial at temperature 1.0, code and chat, 1/2/4 streams, 256 tokens, 3 reps (the
# sampled cells of sampled0014.sh). Serve settings, lock and restore as sampled0014.sh. Tables: sampled0014_pool.py
# over this run and sampled0014.sh's.
set -u
SELF=$(readlink -f "$0")
cd ~/work/target || exit 1
if [ "${SAMPLED_LOCKED:-}" != 1 ]; then
  mkdir -p bench
  flock -o -w 7200 ~/work/gpu.lock env SAMPLED_LOCKED=1 bash "$SELF"
  echo "sampled0014b exit $? $(date -Is)" >> bench/sampled0014b.exit
  exit
fi
OUT=bench/sampled0014b; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
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
for f in $UP/bench_concurrent.py $UP/bench_openai.py "$SELF"; do log "SHA256 $(sha256sum "$f" | cut -c1-16) $f"; done
for im in um um14; do log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"; done
boot() { # dir image [env...]
  local d=$1 img=$2; shift 2
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(gpu)"
  log "ENV $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null | grep -E '^TF_FLASHNEXT_MTP' | tr '\n' ' ')"
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
  local c=(--tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 1.0)
  if boot "$d" "$img" "$@"; then
    if [ "$name" = main-1 ]; then
      run "$d" soak python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --label soak --output "$d/soak.json"
    fi
    run "$d" decode_t1 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 9 --temperatures 1.0 \
        --label "$name" --output "$d/decode_t1.json"
    run "$d" on_t1 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --label "$name-on" --output "$d/on_t1.json"
  fi
  down "$d"
}
arm main-1 um
arm pr-default-1 um14
arm pr-mxfp8-1 um14 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
arm pr-mxfp8-2 um14 TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
arm pr-default-2 um14
arm main-2 um
python3 sampled0014_pool.py "$OUT/pool.md" bench/sampled0014 "$OUT" >> "$LOG" 2>&1
log "POOL rc $? $(date -Is)"
