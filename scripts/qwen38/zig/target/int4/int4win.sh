#!/usr/bin/env bash
# int4win.sh CELL... - one GPU window on spark6: each CELL is kind:name:streams[:ENV...] with kind ours|prod.
# ours boots tensorfold-qwen38:$IMG through the campaign recipe on the INT4-AutoRound checkpoint (fp8 KV, 262,144
# window, VISION=0, HOST=127.0.0.1); prod boots production's own launcher. Per cell: golden at one stream (GOLD=1),
# fixed chat prompts (CHAT=1), one decode pass of prose and code, the boot log. GUARD=1: an ours golden at one stream
# whose first reply is not production's "Paris" ends the window. Production is restored at the end (and on any
# exit) and /health is checked. The GPU lock is held for the whole window. CKPT names the recipe's checkpoint
# (default int4; nvfp4 for the FP4-Local checkpoint).
set -u
IMG=${IMG:-tensorfold-qwen38:int4a}
OUT=${OUT:-$HOME/work/int4/bench}
CKPT=${CKPT:-int4}
mkdir -p "$OUT"
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/restore.log" 2>&1
  echo "=== restored $(date -Is) health $(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:8888/health)"
}
chat() { # out
  local i=0
  while IFS= read -r p; do
    i=$((i + 1))
    curl -s -m 600 http://127.0.0.1:8888/v1/chat/completions -H 'Content-Type: application/json' \
      -d "{\"model\":\"Qwen3.8-Flash-Next\",\"messages\":[{\"role\":\"user\",\"content\":\"$p\"}],\"max_tokens\":160,\"temperature\":0,\"chat_template_kwargs\":{\"enable_thinking\":false}}" > "$1/chat$i.json"
  done < "$HOME/work/int4/chat_prompts.txt"
}
cell() { # kind name streams env...
  local kind=$1 name=$2 c=$3; shift 3
  local out="$OUT/$name-c$c"; mkdir -p "$out"
  if [ "$kind" = prod ]; then
    ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
    ( env LOCK_HOLDER=0 PARALLEL="$c" HOST=127.0.0.1 ~/qwen6-start-prod.sh </dev/null ) > "$out/boot.log" 2>&1
  else
    ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="$IMG" CHECKPOINT="$CKPT" VISION=0 \
        TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL="$c" CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 \
        WAIT_TIMEOUT=3600 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  fi
  echo "=== $name C=$c $(date -Is) gpu $(nvidia-smi --query-gpu=temperature.gpu,clocks.sm --format=csv,noheader | tr -d ' ') $(grep -a -m1 -E 'answered|ERROR|rror:' "$out/boot.log" | cut -c1-200)"
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  if curl -s -o /dev/null -m 5 http://127.0.0.1:8888/health; then
    [ "${GOLD:-0}" = 1 ] && [ "$c" = 1 ] && ( cd ~/work && timeout 1200 python3 qf_harness.py golden "$out/zgold.json" 2>&1 | tail -1 )
    [ "${CHAT:-0}" = 1 ] && [ "$c" = 1 ] && chat "$out"
    timeout 2400 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "i4-$name-c$c" "$c" "$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
    docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  else
    grep -a -E "error|panic|refus|Unsupported|Unexpected" "$out/logs.txt" | head -8 | cut -c1-240
  fi
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
}
(
  flock 9
  echo "=== lock $(date -Is)"
  trap restore EXIT
  for spec in "$@"; do
    IFS=: read -r kind name c envs <<< "$spec"
    # shellcheck disable=SC2086
    cell "$kind" "$name" "$c" $envs
    if [ "${GUARD:-0}" = 1 ] && [ "$kind" = ours ] && [ "$c" = 1 ] && ! grep -q '"content": "Paris' "$OUT/$name-c$c/zgold.json" 2>/dev/null; then
      echo "=== guard: $name golden-0 is not Paris, window ends"
      break
    fi
  done
) 9>"$HOME/work/gpu.lock"
touch "$OUT/DONE"
