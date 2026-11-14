#!/usr/bin/env bash
# receipt0015.sh BASE [full|rerun] - the TF_FLASHNEXT_MTP_WEIGHTS receipt on upstream main at BASE, as the maintainer
# set it on #3162: main (image um15) against the branch rebased on BASE (um15x), alternating M1 U1 X1 M2 X2 U2, one
# fresh boot an arm (U = the setting unset, U2 with it set blank; X = mxfp8). Each arm: tools/bench_openai.py greedy
# (3 reps) and at temperature 1.0 (9 seeds), tools/bench_concurrent.py --alone --serial greedy and at temperature 1.0
# with seeds 1234, 2234 and 3234 (1/2/4 streams, 256 tokens, 3 reps), /metrics around each, then ttft.py's cold 8k and
# 32k prompts. Then a start with a malformed value and the exactness arms of exact0014.sh (main, unset, mxfp8; prompt
# cache on and off). `rerun` boots M3 U3 X3 M4 X4 U4 for the invocations named in rerun.txt (the noise rule's one
# rerun). NVFP4, bf16 KV, 131,072 window, --parallel 4. GPU lock held throughout; production restored on every exit.
set -u
SELF=$(readlink -f "$0")
cd ~/work/target || exit 1
if [ "${R15_LOCKED:-}" != 1 ]; then
  mkdir -p bench
  flock -o -w 43200 ~/work/gpu.lock env R15_LOCKED=1 bash "$SELF" "$@"
  echo "receipt0015 $* exit $? $(date -Is)" >> bench/receipt0015.exit
  exit
fi
BASE=${1:?upstream main sha}
MODE=${2:-full}
OUT=bench/receipt0015; mkdir -p "$OUT"; LOG=$OUT/run-$MODE.log; : > "$LOG"; rm -f "$OUT/DONE-$MODE"
UP=up-tools15
X=exact15
URL=http://127.0.0.1:8080
MODEL=
log() { echo "$*" >> "$LOG"; }
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' '; }
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/prod-$MODE.out" 2>&1
  log "RESTORE prod /health $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health) $(date -Is)"
  touch "$OUT/DONE-$MODE"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
log "START $MODE $(date -Is) base $BASE"
if [ "$MODE" = full ]; then
  T=~/work/lanes/up-pr/tf
  git -C $T fetch -q https://github.com/ashhart/TensorFold.git main
  git -C $T cat-file -e "$BASE^{commit}" || { log "base $BASE not fetched"; exit 1; }
  git -C $T update-ref refs/heads/um15-main "$BASE"
  rm -rf $UP && mkdir -p $UP && git -C $T archive "$BASE" tools | tar -x --strip-components=1 -C $UP && echo "$BASE" > $UP/BASE_SHA
  rm -rf $X && cp -r exact $X && git -C $T show "$BASE:zig/tests/qwen35/serve_check.py" > $X/serve_check.py
  if ! docker image inspect tensorfold-qwen38:um15 > /dev/null 2>&1; then
    bash ~/work/merge/build-br.sh um15 git://192.168.99.16/up-pr/tf "$BASE" > build-um15.out 2>&1
    log "BUILD um15 rc $? $(grep -aE '^BUILT' build-um15.out | head -1)"
  fi
  BASE=$BASE bash ./build_rung.sh um15x rungs127/pr0015.patch >> "$LOG" 2>&1
fi
for f in $UP/bench_concurrent.py $UP/bench_openai.py $X/serve_check.py rungs127/pr0015.patch "$SELF"; do log "SHA256 $(sha256sum "$f" | cut -c1-16) $f"; done
for im in um15 um15x; do
  docker image inspect tensorfold-qwen38:$im > /dev/null 2>&1 || { log "image $im missing"; exit 1; }
  log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"
done
boot() { # dir image on|off [env...]
  local d=$1 img=$2 cache=$3; shift 3
  local extra=(); [ "$cache" = off ] && extra=(--prompt-cache-gib 0)
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart "${extra[@]}" </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(gpu)"
  log "ENV $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null | grep -E '^TF_FLASHNEXT_MTP' | sed 's/$/|/' | tr '\n' ' ')"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  [ -n "$MODEL" ]
}
down() { # dir
  docker logs qwen38-flash-next-tf > "$1/server.log" 2>&1
  grep -a -m2 'MTP_WEIGHTS\|re-coded' "$1/server.log" | cut -c1-200 | sed 's/^/LOG /' >> "$LOG"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
metrics() { curl -s $URL/metrics | grep -aE '^[a-z:_]*mtp_(drafted|accepted)_total' | tr '\n' ' '; }
run() { # dir name command...
  local d=$1 name=$2; shift 2
  echo "$name before $(metrics)" >> "$d/metrics.txt"
  "$@" > "$d/$name.out" 2>&1
  local rc=$?
  echo "$name after $(metrics)" >> "$d/metrics.txt"
  log "RC $d $name $rc $(date -Is) gpu $(gpu)"
}
wanted() { [ "$MODE" = full ] || grep -qx "$1" "$OUT/rerun.txt"; }
speed() { # name image [env...]
  local name=$1 img=$2; shift 2
  local d=$OUT/$name
  local c=(--tokens 256 --reps 3 --levels 1,2,4 --alone --serial)
  if boot "$d" "$img" on "$@"; then
    [ "$name" = M1 ] && run "$d" soak python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label soak --output "$d/soak.json"
    wanted openai_t0 && run "$d" openai_t0 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 3 --temperatures 0 --label "$name" --output "$d/openai_t0.json"
    wanted openai_t1 && run "$d" openai_t1 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 9 --temperatures 1.0 --label "$name" --output "$d/openai_t1.json"
    wanted conc_t0 && run "$d" conc_t0 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label "$name" --output "$d/conc_t0.json"
    for s in 1234 2234 3234; do
      wanted conc_t1_s$s && run "$d" conc_t1_s$s python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 1.0 --seed $s --label "$name" --output "$d/conc_t1_s$s.json"
    done
    [ "$MODE" = full ] && run "$d" ttft python3 ~/work/bench/ttft.py 8080 --sizes 8k,32k --thinking off --warm-add 0 --loads idle --reps 3
  fi
  down "$d"
}
exact() { # name image [env...]
  local name=$1 img=$2; shift 2
  local d=$OUT/exact/$name
  if boot "$d/on" "$img" on "$@"; then
    run "$d/on" concurrent python3 $UP/bench_concurrent.py $URL "$MODEL" --tokens 256 --reps 3 \
        --temperatures 1.0,0 --levels 1,2,4 --alone --serial --label "$name" --output "$d/on/concurrent.json"
    run "$d/on" golden python3 $UP/bench_concurrent.py $URL "$MODEL" --tokens 256 --reps 1 --temperatures 0 \
        --levels 1,2,4,6 --prompts $X/golden.json --alone --serial --label "$name-golden" --output "$d/on/golden.json"
    run "$d/on" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/on/drafts.json"
    run "$d/on" turns python3 $X/served_exactness.py turns $URL "$MODEL" $X/turns.json "$d/on/turns.json"
    run "$d/on" cache python3 $UP/bench_cache.py $URL "$MODEL" --tokens 256 --repeats 2 --streams 2 --output "$d/on/cache.json"
  fi
  down "$d/on"
  if boot "$d/off" "$img" off "$@"; then
    run "$d/off" fresh python3 $X/served_exactness.py fresh $URL "$MODEL" "$d/on/turns.json" "$d/off/fresh.json"
    run "$d/off" drafts python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/off/drafts.json"
    run "$d/off" serve_check python3 $X/serve_check.py $URL "$MODEL" 256
  fi
  down "$d/off"
}
if [ "$MODE" = full ]; then
  speed M1 um15
  speed U1 um15x
  speed X1 um15x TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
  speed M2 um15
  speed X2 um15x TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
  speed U2 um15x TF_FLASHNEXT_MTP_WEIGHTS=
  boot "$OUT/malformed" um15x off TF_FLASHNEXT_MTP_WEIGHTS=MXFP8
  log "MALFORMED boot rc $? $(grep -a -m1 'TF_FLASHNEXT_MTP_WEIGHTS' "$OUT/malformed/boot.log" | cut -c1-240)"
  down "$OUT/malformed"
  exact main um15
  exact pr-default um15x
  exact pr-mxfp8 um15x TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
  python3 $X/exact0014_sum.py "$OUT/exact" > "$OUT/exact/summary.md" 2>&1
  log "EXACT SUMMARY rc $? $(date -Is)"
else
  speed M3 um15
  speed U3 um15x
  speed X3 um15x TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
  speed M4 um15
  speed X4 um15x TF_FLASHNEXT_MTP_WEIGHTS=mxfp8
  speed U4 um15x
fi
python3 sum15.py "$OUT" >> "$LOG" 2>&1
log "SUM rc $? $(date -Is)"
