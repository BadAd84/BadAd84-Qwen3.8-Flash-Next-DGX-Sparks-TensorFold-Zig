#!/bin/bash
# ARM=stock: the recipe's v1.1.4 published image (~/work/lanes/rpr/recipe) on NVIDIA FP4, the recipe's defaults:
#   v1.1.4's engine rejects the INT4-AutoRound layout (UnsupportedCheckpoint), so the matrix is cross-quant (stated).
# ARM=ours:  the serve as configured (~/qwen6-start.sh: zmerge8-kfix on INT4, the measured zmerge8 env, warm turns off).
# Fresh boot at PARALLEL=C bound to 127.0.0.1, health counter before/after, GPU temperature at each window,
# golden 6/6 (gates ours; recorded for stock, whose engine owes the 1.0.0 reference nothing), decode with every slot
# busy (3 passes), client TTFT at 1k/8k/32k/120k idle and with C-1 other streams. Output: runs/<ARM>-c<C>/.
set -uo pipefail
ARM=$1 C=$2
L=$HOME/work/lanes/par114 OUT=$HOME/work/lanes/par114/runs/$ARM-c$C
mkdir -p "$OUT" || exit 1
exec > "$OUT/arm.log" 2>&1
temp() { nvidia-smi --query-gpu=temperature.gpu --format=csv,noheader 2>/dev/null | tr -d ' '; }
health() { curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-300; }
echo "=== $ARM C=$C start $(date -Is) temp $(temp)"
t0=$SECONDS
# v1.1.4 fits 5 full 262,144-token windows; 6 and 8 streams do not fit (the recipe's own note), so those stock cells
# run 131,072-token windows. Decode and TTFT at these reply lengths do not depend on the window; the table says so.
CTX=262144; [ "$C" -ge 6 ] && CTX=131072
case "$ARM" in
  stock) ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 CHECKPOINT=nvfp4 PARALLEL="$C" CONTEXT="$CTX" HOST=127.0.0.1 ./start.sh restart </dev/null ) 2>&1 \
           | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20 ;;
  ours)  ( env PARALLEL="$C" HOST=127.0.0.1 LOCK_HOLDER=0 ~/qwen6-start.sh </dev/null ) 2>&1 \
           | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20 ;;
  # Stock upstream TensorFold v1.2.4 (267c5af6) built by build-br.sh without any recipe patch, booted through the
  # v1.1.4 recipe's start.sh on NVIDIA FP4 with vision off (the FP4 vision tower is the recipe's 0001/0002) and
  # bf16 KV (its Flash Next family refuses --kv-cache fp8, which is the recipe's 0003) in 131,072-token windows.
  up124) CTX=131072
         ( cd ~/work/lanes/rpr/recipe && env PREPARE=0 IMAGE=tensorfold-qwen38:up124 CHECKPOINT=nvfp4 VISION=0 KV_DTYPE=bf16 PARALLEL="$C" CONTEXT="$CTX" HOST=127.0.0.1 ./start.sh restart </dev/null ) 2>&1 \
           | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20 ;;
  *) echo "ARM is stock, ours or up124"; exit 1 ;;
esac
echo "BOOT seconds $((SECONDS - t0))"
echo "IMAGE $(docker inspect qwen38-flash-next-tf --format '{{.Config.Image}}' 2>/dev/null)"
docker inspect qwen38-flash-next-tf --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep -E '^(TF_|TENSORFOLD_)' | sort | tr '\n' ' ' | sed 's/^/ENV /'; echo
docker logs qwen38-flash-next-tf > "$OUT/boot.log" 2>&1
grep -a "sequence memory\|graphs:\|drafts:\|loaded in\|compat" "$OUT/boot.log" | cut -c1-240 | sed 's/^/BOOTLOG /'
echo "HEALTH0 $(health)"
curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health || { echo "BOOT FAILED"; exit 1; }
cd "$HOME/work" || exit 1
python3 qf_harness.py golden "$OUT/zgold.json" | tail -1
python3 zgold_cmp.py zab3/zgold-base-c1.json "$OUT/zgold.json" 2>&1 | sed 's/^/GOLD /'
gold=${PIPESTATUS[0]}
echo "GOLD exit $gold"
if [ "$ARM" = ours ] && [ "$gold" != 0 ]; then echo "golden not identical: no speed result"; exit 2; fi
echo "=== $(date +%T) probe dec temp $(temp)"
python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "$ARM-c$C" "$C" "$OUT/dec.jsonl" 3
echo "PROBE dec exit $?"
echo "=== $(date +%T) probe ttft temp $(temp)"
python3 "$HOME/work/bench/ttft.py" 8888 --reps 2 --sizes 1k,8k,32k,120k --thinking off --warm-add 0 \
  --loads "idle,load$((C - 1))" 2>&1 | sed 's/^/TTFT /'
echo "PROBE ttft exit $?"
echo "HEALTH1 $(health)"
docker logs qwen38-flash-next-tf > "$OUT/serve.log" 2>&1
echo "SOURCES $(grep -a '^\[tensorfold\] [0-9a-f.:]* "' "$OUT/serve.log" | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
echo "=== $ARM C=$C DONE $(date -Is) $((SECONDS - t0)) s temp $(temp)"
