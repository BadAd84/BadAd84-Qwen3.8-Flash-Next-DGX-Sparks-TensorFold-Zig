#!/usr/bin/env bash
# ab126.sh ARM C - one cell of a stock-1.2.6 against our-stack A/B on spark6 (repo copy; box copy ~/work/target).
#
# ARM=base:  tensorfold-qwen38:up126 (upstream v1.2.6, built by build-br.sh, no recipe patch)
# ARM=lever: ${LEVER_IMG:-tensorfold-qwen38:stack126} (the 1.2.6 branch with our levers)
# Both boot through the campaign's recipe copy (~/work/lanes/rpr/recipe) with identical settings except the image, so
# a difference is the code: CHECKPOINT=nvfp4, VISION=0, KV_DTYPE=${KV_DTYPE:-bf16}, PARALLEL=C, CONTEXT=${CONTEXT:-131072}.
# Records boot time and memory lines, golden (on its own terms), decode with every slot busy (3 passes, reply shas),
# cold TTFT 1k/8k/32k/120k thinking off and on (idle and under C-1 streams) and the warm +2k next turn.
# Output: ~/work/target/ab126/<arm>-c<C>/.
set -uo pipefail
ARM=${1:?arm} C=${2:?streams}
IMG=tensorfold-qwen38:up126
[ "$ARM" = lever ] && IMG=${LEVER_IMG:-tensorfold-qwen38:stack126}
OUT=$HOME/work/target/ab126/$ARM-c$C
mkdir -p "$OUT" || exit 1
exec > "$OUT/arm.log" 2>&1
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw --format=csv,noheader 2>/dev/null | tr -d ' '; }
health() { curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-300; }
loads=idle
[ "$C" -gt 1 ] && loads="idle,load$((C - 1))"
echo "=== $ARM C=$C image $IMG start $(date -Is) gpu $(gpu)"
t0=$SECONDS
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="$IMG" CHECKPOINT=nvfp4 VISION=0 \
    KV_DTYPE="${KV_DTYPE:-bf16}" PARALLEL="$C" CONTEXT="${CONTEXT:-131072}" HOST=127.0.0.1 ./start.sh restart </dev/null ) 2>&1 \
  | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20
echo "BOOT seconds $((SECONDS - t0))"
curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health || { echo "BOOT FAILED"; exit 1; }
echo "HEALTH0 $(health)"
docker logs qwen38-flash-next-tf > "$OUT/boot.log" 2>&1
grep -a "sequence memory\|graphs:\|drafts:\|loaded in\|copy windows\|walues" "$OUT/boot.log" | cut -c1-240 | sed 's/^/BOOTLOG /'
cd "$HOME/work" || exit 1
python3 qf_harness.py golden "$OUT/zgold.json" | tail -1
echo "=== $(date +%T) decode temp $(gpu)"
python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "$ARM-c$C" "$C" "$OUT/dec.jsonl" 3
echo "PROBE dec exit $?"
echo "=== $(date +%T) ttft temp $(gpu)"
python3 "$HOME/work/bench/ttft.py" 8888 --reps 2 --sizes 1k,8k,32k,120k --thinking off,on \
  --warm-base 100k --warm-add 2k --loads "$loads" 2>&1 | sed 's/^/TTFT /'
echo "PROBE ttft exit $?"
echo "=== $ARM C=$C DONE $(date -Is) $((SECONDS - t0)) s gpu $(gpu)"
