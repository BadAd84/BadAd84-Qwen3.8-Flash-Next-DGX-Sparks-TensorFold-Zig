#!/usr/bin/env bash
# updraft.sh BASE [full|rerun] - the multi-stream draft setting on upstream main alone: main at BASE (image
# tensorfold-qwen38:um<first 8 of BASE>, built by ~/work/merge/build-br.sh when missing, no patch applied), M1 X1 X2 M2,
# one fresh boot an arm: M with the draft settings unset, X with TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8.
# Each arm, with BASE's own tools: bench_openai.py greedy and at temperature 1.0 (seeds 1234 to 1236) and
# bench_concurrent.py --alone --serial greedy and at temperature 1.0 (seed 1234), 256 tokens, 3 reps, 1/2/4 streams,
# /metrics around each (M1 first runs bench_concurrent once as a soak). NVFP4, bf16 KV, 131,072 window, --parallel 4,
# HOST=127.0.0.1 PORT=8080 (receipt0015.sh's boot). `rerun` boots M3 X3 X4 M4 for the invocations named in rerun.txt
# (the noise rule's one rerun). Runs from ~/work/target (sum15.py, blank15.py; output bench/updraft). GPU lock held
# throughout; production restored on every exit.
set -u
SELF=$(readlink -f "$0")
cd ~/work/target || exit 1
if [ "${UD_LOCKED:-}" != 1 ]; then
  mkdir -p bench
  flock -o -w 43200 ~/work/gpu.lock env UD_LOCKED=1 bash "$SELF" "$@"
  echo "updraft $* exit $? $(date -Is)" >> bench/updraft.exit
  exit
fi
BASE=${1:?upstream main sha}
MODE=${2:-full}
IMG=um${BASE:0:8}
X=(TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8)
OUT=bench/updraft; mkdir -p "$OUT"; LOG=$OUT/run-$MODE.log; : > "$LOG"; rm -f "$OUT/DONE-$MODE"
UP=up-tools-ud
T=~/work/lanes/up-pr/tf
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
log "START $MODE $(date -Is) base $BASE image $IMG"
if [ "$MODE" = full ]; then
  git -C $T cat-file -e "$BASE^{commit}" || git -C $T fetch -q https://github.com/ashhart/TensorFold.git main
  git -C $T cat-file -e "$BASE^{commit}" || { log "base $BASE not fetched"; exit 1; }
  git -C $T update-ref refs/heads/umtip-main "$BASE"
  rm -rf $UP && mkdir -p $UP && git -C $T archive "$BASE" tools | tar -x --strip-components=1 -C $UP && echo "$BASE" > $UP/BASE_SHA
  if ! docker image inspect "tensorfold-qwen38:$IMG" > /dev/null 2>&1; then
    bash ~/work/merge/build-br.sh "$IMG" git://192.168.99.16/up-pr/tf "$BASE" > "build-$IMG.out" 2>&1
    log "BUILD $IMG rc $?"
  fi
fi
for f in $UP/bench_concurrent.py $UP/bench_openai.py "$SELF"; do log "SHA256 $(sha256sum "$f" | cut -c1-16) $f"; done
docker image inspect "tensorfold-qwen38:$IMG" > /dev/null 2>&1 || { log "image $IMG missing"; exit 1; }
log "IMAGE $IMG $(docker image inspect -f '{{.Id}}' "tensorfold-qwen38:$IMG" | cut -c8-19)"
boot() { # dir [env...]
  local d=$1; shift
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env "$@" PREPARE=0 IMAGE="tensorfold-qwen38:$IMG" CHECKPOINT=nvfp4 \
      VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 \
      MEM_CHECK=0 ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(gpu)"
  log "ENV $(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' qwen38-flash-next-tf 2>/dev/null | grep -E '^TF_FLASHNEXT_(SHARED_DRAFTS|GREEDY_WIDE|CONFIDENCE|DRAFTS)' | sed 's/$/|/' | tr '\n' ' ')"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  [ -n "$MODEL" ]
}
down() { # dir
  docker logs qwen38-flash-next-tf > "$1/server.log" 2>&1
  grep -a -m3 -E 'overrides|streams? at once' "$1/server.log" | cut -c1-240 | sed 's/^/LOG /' >> "$LOG"
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
speed() { # name [env...]
  local name=$1; shift
  local d=$OUT/$name
  local c=(--tokens 256 --reps 3 --levels 1,2,4 --alone --serial)
  if boot "$d" "$@"; then
    [ "$name" = M1 ] && run "$d" soak python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label soak --output "$d/soak.json"
    wanted openai_t0 && run "$d" openai_t0 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 3 --temperatures 0 --label "$name" --output "$d/openai_t0.json"
    wanted openai_t1 && run "$d" openai_t1 python3 $UP/bench_openai.py $URL "$MODEL" --tokens 256 --reps 3 --temperatures 1.0 --label "$name" --output "$d/openai_t1.json"
    wanted conc_t0 && run "$d" conc_t0 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 0 --label "$name" --output "$d/conc_t0.json"
    wanted conc_t1_s1234 && run "$d" conc_t1_s1234 python3 $UP/bench_concurrent.py $URL "$MODEL" "${c[@]}" --temperatures 1.0 --seed 1234 --label "$name" --output "$d/conc_t1_s1234.json"
  fi
  down "$d"
}
if [ "$MODE" = full ]; then
  speed M1
  speed X1 "${X[@]}"
  speed X2 "${X[@]}"
  speed M2
else
  speed M3
  speed X3 "${X[@]}"
  speed X4 "${X[@]}"
  speed M4
fi
python3 sum15.py "$OUT" >> "$LOG" 2>&1
log "SUM rc $? $(date -Is)"
python3 blank15.py "$OUT" > "$OUT/hashes-$MODE.txt" 2>&1
log "HASHES rc $? $(date -Is)"
