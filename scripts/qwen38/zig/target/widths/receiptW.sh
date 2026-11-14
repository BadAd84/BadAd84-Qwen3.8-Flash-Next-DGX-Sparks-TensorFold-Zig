#!/usr/bin/env bash
# receiptW.sh BASE PATCH - the widths step (#3368 step 1) on upstream main at BASE: main (image wm) against main plus
# PATCH (wb), alternating M1 B1 B2 M2, one fresh boot an arm. Each arm: tools/bench_concurrent.py --alone --serial
# greedy at 1/2/4 streams (256 tokens, 3 reps) and tools/bench_openai.py greedy (3 reps), /metrics around each, the
# boot's resident memory. NVFP4, bf16 KV, 131,072 window, --parallel 4, as the #3162/#3218 receipts. GPU lock held
# throughout; production restored on every exit. Output: ~/work/widths/receipt/.
set -u
SELF=$(readlink -f "$0")
if [ "${RW_LOCKED:-}" != 1 ]; then
  flock -o -w 43200 ~/work/gpu.lock env RW_LOCKED=1 bash "$SELF" "$@"
  exit
fi
BASE=${1:?upstream main sha}
PATCH=${2:?branch patch}
cd ~/work/target || exit 1
OUT=$HOME/work/widths/receipt; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
UP=$HOME/work/widths/tools
URL=http://127.0.0.1:8080
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
log "START $(date -Is) base $BASE patch $(sha256sum "$PATCH" | cut -c1-16)"
T=~/work/lanes/up-pr/tf
git -C $T fetch -q https://github.com/ashhart/TensorFold.git main
git -C $T cat-file -e "$BASE^{commit}" || { log "base $BASE not fetched"; exit 1; }
rm -rf "$UP" && mkdir -p "$UP" && git -C $T archive "$BASE" tools | tar -x --strip-components=1 -C "$UP"
if ! docker image inspect tensorfold-qwen38:wm > /dev/null 2>&1; then
  bash ~/work/merge/build-br.sh wm git://192.168.99.16/up-pr/tf "$BASE" > "$OUT/build-wm.out" 2>&1
  log "BUILD wm rc $? $(grep -aE '^BUILT' "$OUT/build-wm.out" | head -1)"
fi
BASE=$BASE bash ./build_rung.sh wb "$PATCH" > "$OUT/build-wb.out" 2>&1
log "BUILD wb rc $? $(grep -aE '^BUILT|error' "$OUT/build-wb.out" | head -2 | tr '\n' ' ')"
for im in wm wb; do
  docker image inspect tensorfold-qwen38:$im > /dev/null 2>&1 || { log "image $im missing"; exit 1; }
  log "IMAGE $im $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:$im | cut -c8-19)"
done
ls ~/.cache/huggingface/hub | grep -i -E 'mlx|4bit' | sed 's/^/MLX-CACHE /' >> "$LOG"
boot() { # dir image
  local d=$1 img=$2
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  log "=== $d $(date -Is) boot rc $rc gpu $(gpu)"
  [ "$rc" = 0 ] || return 1
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  log "MEM $d $(docker stats --no-stream --format '{{.MemUsage}}' qwen38-flash-next-tf) | $(docker logs qwen38-flash-next-tf 2>&1 | grep -a -m1 -o 'model [0-9.]* GiB[^|]*' | cut -c1-200)"
  log "CHECK $d $(docker logs qwen38-flash-next-tf 2>&1 | grep -a -m1 -o 'window self-check: [0-9]* of [0-9]*')"
  [ -n "$MODEL" ]
}
down() { # dir
  docker logs qwen38-flash-next-tf > "$1/server.log" 2>&1
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
metrics() { curl -s $URL/metrics | grep -aE '^[a-z:_]*(mtp_(drafted|accepted)_total|decode_rounds_total)' | tr '\n' ' '; }
run() { # dir name command...
  local d=$1 name=$2; shift 2
  echo "$name before $(metrics)" >> "$d/metrics.txt"
  "$@" > "$d/$name.out" 2>&1
  local rc=$?
  echo "$name after $(metrics)" >> "$d/metrics.txt"
  log "RC $d $name $rc $(date -Is) gpu $(gpu)"
}
arm() { # name image
  local d=$OUT/$1
  if boot "$d" "$2"; then
    run "$d" conc_t0 python3 "$UP/bench_concurrent.py" $URL "$MODEL" --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 0 --label "$1" --output "$d/conc_t0.json"
    run "$d" openai_t0 python3 "$UP/bench_openai.py" $URL "$MODEL" --tokens 256 --reps 3 --temperatures 0 --label "$1" --output "$d/openai_t0.json"
  fi
  down "$d"
}
arm M1 wm
arm B1 wb
arm B2 wb
arm M2 wm
log "ARMS DONE $(date -Is)"
