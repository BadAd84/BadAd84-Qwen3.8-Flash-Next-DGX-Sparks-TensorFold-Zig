#!/usr/bin/env bash
# bench_arm.sh ARM C - one cell of the overnight 1.2.6 patch sweep on spark6 (repo copy; box copy ~/work/target).
# Boots tensorfold-qwen38:$IMG through the campaign recipe (KV_DTYPE, CONTEXT, PARALLEL=C, localhost), records boot
# time/memory/golden, decode with every slot busy (3 passes, reply shas) and cold TTFT at 1k/8k/32k/120k thinking
# off and on, idle and under C-1 streams. Output: ~/work/target/bench/$ARM/c<C>/.
set -uo pipefail
ARM=${1:?arm} C=${2:?streams}
IMG=${IMG:-tensorfold-qwen38:up126}
CHKPT=${CHKPT:-nvfp4}
OUT=$HOME/work/target/bench/$ARM/c$C
mkdir -p "$OUT" || exit 1
exec > "$OUT/arm.log" 2>&1
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw --format=csv,noheader 2>/dev/null | tr -d ' '; }
loads=idle
[ "$C" -gt 1 ] && loads="idle,load$((C - 1))"
echo "=== $ARM C=$C image $IMG kv ${KV_DTYPE:-bf16} ctx ${CONTEXT:-131072} ckpt $CHKPT start $(date -Is) gpu $(gpu)"
t0=$SECONDS
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="$IMG" CHECKPOINT="$CHKPT" VISION=0 TENSORFOLD_CUDA_KERNELS=native \
    KV_DTYPE="${KV_DTYPE:-bf16}" PARALLEL="$C" CONTEXT="${CONTEXT:-131072}" HOST=127.0.0.1 ${ARM_ENV:-} ./start.sh restart </dev/null ) 2>&1 \
  | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20
echo "BOOT seconds $((SECONDS - t0))"
curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health || { echo "BOOT FAILED"; exit 1; }
docker logs qwen38-flash-next-tf > "$OUT/boot.log" 2>&1
grep -a "streams at once\|sequence memory\|graphs:\|loaded in\|self-check\|copy windows" "$OUT/boot.log" | cut -c1-230 | sed 's/^/BOOTLOG /'
cd "$HOME/work" || exit 1
python3 qf_harness.py golden "$OUT/zgold.json" | tail -1
echo "GOLD exit $?"
echo "=== $(date +%T) decode temp $(gpu)"
python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "$ARM-c$C" "$C" "$OUT/dec.jsonl" 3
echo "PROBE dec exit $?"
echo "=== $(date +%T) ttft temp $(gpu)"
python3 "$HOME/work/bench/ttft.py" 8888 --reps 2 --sizes 1k,8k,32k,120k --thinking off,on \
  --warm-base 100k --warm-add 2k --loads "$loads" 2>&1 | sed 's/^/TTFT /'
echo "PROBE ttft exit $?"
echo "=== $ARM C=$C DONE $(date -Is) $((SECONDS - t0)) s gpu $(gpu)"
