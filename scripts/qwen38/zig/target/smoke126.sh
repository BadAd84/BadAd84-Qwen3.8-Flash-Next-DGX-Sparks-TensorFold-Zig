#!/usr/bin/env bash
# smoke126.sh ARM [C] - boot one 1.2.6 image through the campaign recipe copy and prove it serves:
# health, golden 6/6 (written for a cross-arm diff), one decode pass with every slot busy and a boot-log summary.
# ARM=base uses up126, ARM=lever uses ${LEVER_IMG:-stack126}. KV_DTYPE/CONTEXT default to fp8 / 262144.
set -uo pipefail
ARM=${1:?arm} C=${2:-8}
IMG=tensorfold-qwen38:up126
[ "$ARM" = lever ] && IMG=${LEVER_IMG:-tensorfold-qwen38:stack126}
OUT=$HOME/work/target/smoke/$ARM
mkdir -p "$OUT" || exit 1
exec > "$OUT/smoke.log" 2>&1
echo "=== smoke $ARM C=$C image $IMG $(date -Is)"
t0=$SECONDS
( cd "$HOME/work/lanes/rpr/recipe" && env PREPARE=0 IMAGE="$IMG" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
    KV_DTYPE="${KV_DTYPE:-fp8}" PARALLEL="$C" CONTEXT="${CONTEXT:-262144}" HOST=127.0.0.1 ./start.sh restart </dev/null ) 2>&1 \
  | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20
echo "BOOT seconds $((SECONDS - t0))"
curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health || { echo "BOOT FAILED"; exit 1; }
docker logs qwen38-flash-next-tf > "$OUT/boot.log" 2>&1
grep -a "sequence memory\|graphs:\|drafts:\|loaded in\|copy windows\|serving .* at" "$OUT/boot.log" | cut -c1-220 | sed 's/^/BOOTLOG /'
cd "$HOME/work" || exit 1
python3 qf_harness.py golden "$OUT/zgold.json" | tail -1
echo "GOLD exit $?"
python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "smoke-$ARM" "$C" "$OUT/dec.jsonl" 1 prose,code
echo "DEC exit $?"
curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-200
echo "=== smoke $ARM done $(date -Is) $((SECONDS - t0)) s"
