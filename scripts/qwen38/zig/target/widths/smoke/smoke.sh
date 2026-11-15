#!/usr/bin/env bash
# smoke.sh - device smoke of the widths step on spark6: widen.py builds a top-5, 1280-wide-shared checkpoint from the
# FP4-Local snapshot (hard links plus one new shard), then, under the GPU lock: the branch image (wb) boots it and runs
# bench_concurrent --alone --serial (greedy, code and chat, 1/2/4 streams), served_exactness drafts, bench_openai and a
# sample reply, with /metrics around them; then main's image (wm) boots the same checkpoint, which it must refuse.
# Production is restored on every exit; the widened checkpoint is removed at the end. Output: ~/work/widths/smoke/.
set -u
SELF=$(readlink -f "$0")
S=$HOME/work/widths/smoke
SNAP=$HOME/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300
HFC=$S/hf
SUB=hub/models--int4port--top5w1280/snapshots/smoke
if [ "${SM_LOCKED:-}" != 1 ]; then
  if [ ! -f "$HFC/$SUB/model.safetensors.index.json" ]; then
    python3 "$S/widen.py" "$SNAP" "$HFC/$SUB" > "$S/widen.out" 2>&1 || { echo "widen failed"; cat "$S/widen.out"; exit 1; }
  fi
  flock -o -w 43200 ~/work/gpu.lock env SM_LOCKED=1 bash "$SELF" "$@"
  exit
fi
OUT=$S/run; mkdir -p "$OUT"; LOG=$OUT/run.log; : > "$LOG"; rm -f "$OUT/DONE"
UP=$HOME/work/widths/tools
X=$HOME/work/target/exact15
URL=http://127.0.0.1:8080
log() { echo "$*" >> "$LOG"; }
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/prod.out" 2>&1
  log "RESTORE prod /health $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health) $(date -Is)"
  touch "$OUT/DONE"
}
trap restore EXIT
trap 'exit 130' INT TERM HUP
log "START $(date -Is) $(tail -1 "$S/widen.out")"
boot() { # dir image
  local d=$1 img=$2
  mkdir -p "$d"
  ( cd ~/work/lanes/rpr/recipe && timeout 900 env PREPARE=0 IMAGE="tensorfold-qwen38:$img" CHECKPOINT=nvfp4 VISION=0 \
      HF_CACHE="$HFC" MODEL_ID=int4port/top5w1280 MODEL_REVISION=smoke \
      TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=bf16 PARALLEL=4 CONTEXT=131072 HOST=127.0.0.1 PORT=8080 MEM_CHECK=0 \
      ./start.sh restart </dev/null ) > "$d/boot.log" 2>&1
  local rc=$?
  docker logs qwen38-flash-next-tf > "$d/server.log" 2>&1
  log "=== $d $img $(date -Is) boot rc $rc"
  return $rc
}
metrics() { curl -s $URL/metrics | grep -aE '^[a-z:_]*(mtp_(drafted|accepted)_total|decode_rounds_total)' | tr '\n' ' '; }
if boot "$OUT/branch" wb; then
  d=$OUT/branch
  MODEL=$(curl -s $URL/v1/models | python3 -c 'import json,sys; print(json.load(sys.stdin)["data"][0]["id"])')
  log "MEM $(docker stats --no-stream --format '{{.MemUsage}}' qwen38-flash-next-tf) | $(grep -a -m1 -o 'model [0-9.]* GiB[^|]*' "$d/server.log" | cut -c1-160)"
  echo "before $(metrics)" > "$d/metrics.txt"
  python3 "$UP/bench_concurrent.py" $URL "$MODEL" --tokens 256 --reps 1 --levels 1,2,4 --alone --serial --temperatures 0 \
      --label top5 --output "$d/conc.json" > "$d/conc.out" 2>&1; log "RC conc $?"
  echo "after_conc $(metrics)" >> "$d/metrics.txt"
  python3 $X/served_exactness.py drafts $URL "$MODEL" $X/prompts.json "$d/drafts.json" > "$d/drafts.out" 2>&1; log "RC drafts $?"
  python3 "$UP/bench_openai.py" $URL "$MODEL" --tokens 256 --reps 3 --temperatures 0 --label top5 --output "$d/openai.json" > "$d/openai.out" 2>&1
  log "RC openai $?"
  echo "after_openai $(metrics)" >> "$d/metrics.txt"
  curl -s $URL/v1/chat/completions -H 'Content-Type: application/json' -d "{\"model\":\"$MODEL\",\"max_tokens\":120,\"temperature\":0,\"messages\":[{\"role\":\"user\",\"content\":\"Explain in three sentences why the sky is blue.\"}],\"chat_template_kwargs\":{\"enable_thinking\":false}}" > "$d/sample.json"
  log "RC sample $?"
  docker logs qwen38-flash-next-tf > "$d/server.log" 2>&1
fi
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
boot "$OUT/main" wm
log "MAIN boot rc $? $(grep -a -h -E 'num_experts_per_tok|shared_expert_intermediate_size|error' "$OUT/main/boot.log" "$OUT/main/server.log" | head -3 | tr '\n' ' ' | cut -c1-300)"
( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
rm -rf "$HFC"
log "ARMS DONE $(date -Is)"
