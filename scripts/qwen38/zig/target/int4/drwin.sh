#!/usr/bin/env bash
# drwin.sh CELL... - drafter arms in one GPU window on spark6: each CELL is kind:name:streams[:ENV...], kind ours|prod.
# ours boots tensorfold-qwen38:$IMG on the INT4-AutoRound checkpoint (fp8 KV, 262,144 window, VISION=0,
# HOST=127.0.0.1) with ENV; prod boots production's own launcher. One stream: the per-prompt draft probe (dprobe.py:
# golden prompts, prose, code); more streams: one decode pass (tfm_decode.py) with its counters. The boot's window
# self-check is kept. Production is restored at the end and on any exit; the GPU lock is held for the window.
set -u
IMG=${IMG:-tensorfold-qwen38:int4d}
OUT=${OUT:-$HOME/work/int4/bench-dr}
mkdir -p "$OUT"
restore() {
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) > "$OUT/restore.log" 2>&1
  echo "=== restored $(date -Is) health $(curl -s -o /dev/null -w '%{http_code}' -m 10 http://127.0.0.1:8888/health)"
}
cell() { # kind name streams env...
  local kind=$1 name=$2 c=$3; shift 3
  local out="$OUT/$name-c$c"; mkdir -p "$out"
  ( cd ~/work/lanes/rpr/recipe && ./stop.sh ) > /dev/null 2>&1
  if [ "$kind" = prod ]; then
    ( env LOCK_HOLDER=0 PARALLEL="$c" HOST=127.0.0.1 ~/qwen6-start-prod.sh </dev/null ) > "$out/boot.log" 2>&1
  else
    ( cd ~/work/lanes/rpr/recipe && env "$@" PREPARE=0 IMAGE="$IMG" CHECKPOINT=int4 VISION=0 \
        TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL="$c" CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 \
        WAIT_TIMEOUT=3600 ./start.sh restart </dev/null ) > "$out/boot.log" 2>&1
  fi
  docker logs qwen38-flash-next-tf > "$out/logs.txt" 2>&1
  echo "=== $name C=$c [$*] $(date -Is) $(grep -a -m1 -E 'answered|ERROR|rror:' "$out/boot.log" | cut -c1-120) | $(grep -a -m1 -o 'window self-check: [0-9]* of [0-9]*' "$out/logs.txt")"
  if curl -s -o /dev/null -m 5 http://127.0.0.1:8888/health; then
    if [ "$c" = 1 ]; then
      ( cd ~/work && timeout 1800 python3 ~/work/int4/dprobe.py "$name" "$out/probe.jsonl" 2>&1 | grep -a "^PROBE" | cut -c1-190 )
    else
      timeout 2400 python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "dr-$name-c$c" "$c" "$out/dec.jsonl" 1 2>&1 | grep -a "^DEC" | cut -c1-200
    fi
  else
    grep -a -E "error|panic|refus|Unsupported|Unexpected" "$out/logs.txt" | head -6 | cut -c1-200
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
  done
) 9>"$HOME/work/gpu.lock"
touch "$OUT/DONE"
