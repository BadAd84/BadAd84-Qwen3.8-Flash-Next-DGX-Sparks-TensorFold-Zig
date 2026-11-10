#!/usr/bin/env bash
# target_arm.sh C - one cell of the production target matrix (spark6, ~/work/target; the repo copy is the source).
#
# A fresh boot of the zmerge8-kfix production serve at PARALLEL=C bound to 127.0.0.1, then: boot time and memory lines,
# golden 6/6 against the 1.0.0 INT4 reference, decode with every slot busy (prose and code, 3 passes, per-stream and
# aggregate, reply shas), client TTFT on cold 1k/8k/32k/120k prompts thinking off AND on, each idle and with C-1 other
# streams decoding, and a warm +2k next turn on a kept 100k conversation. /health and the GPU's temperature, SM clock,
# power and used memory are recorded at every window. Output: runs/c<C>/.
set -uo pipefail
C=${1:?streams}
OUT=$HOME/work/target/runs/c$C
mkdir -p "$OUT" || exit 1
exec > "$OUT/arm.log" 2>&1
gpu() { nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw,memory.used --format=csv,noheader 2>/dev/null | tr -d ' '; }
health() { curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-300; }
loads=idle
[ "$C" -gt 1 ] && loads="idle,load$((C - 1))"
echo "=== cell C=$C start $(date -Is) gpu $(gpu)"
t0=$SECONDS
# qwen6-start-prod.sh is the production recipe copy (~/qwen-zig-prod, the 1.0.0 tree whose start.sh gates
# tf.kernels=present); ~/qwen-zig is the v1.1.4 recipe and refuses this image at its label check.
( env PARALLEL="$C" HOST=127.0.0.1 LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 \
  | grep -a "answered\|LIVE\|refus\|rror\|ERROR\|needs" | head -20
echo "BOOT seconds $((SECONDS - t0))"
echo "IMAGE $(docker inspect qwen38-flash-next-tf --format '{{.Config.Image}}' 2>/dev/null)"
docker inspect qwen38-flash-next-tf --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null \
  | grep -E '^(TF_|TENSORFOLD_)' | sort | tr '\n' ' ' | sed 's/^/ENV /'; echo
docker logs qwen38-flash-next-tf > "$OUT/boot.log" 2>&1
grep -a "sequence memory\|graphs:\|drafts:\|loaded in\|compat\|rows\|window" "$OUT/boot.log" | cut -c1-240 | sed 's/^/BOOTLOG /'
echo "HEALTH0 $(health)"
curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health || { echo "BOOT FAILED"; exit 1; }
cd "$HOME/work" || exit 1
python3 qf_harness.py golden "$OUT/zgold.json" | tail -1
python3 zgold_cmp.py zab3/zgold-base-c1.json "$OUT/zgold.json" 2>&1 | sed 's/^/GOLD /'
echo "GOLD exit $?"
echo "=== $(date +%T) decode temp $(gpu)"
python3 "$HOME/work/lanes/tfmain/tfm_decode.py" "prod-c$C" "$C" "$OUT/dec.jsonl" 3
echo "PROBE dec exit $?"
echo "=== $(date +%T) ttft temp $(gpu)"
python3 "$HOME/work/bench/ttft.py" 8888 --reps 2 --sizes 1k,8k,32k,120k --thinking off,on \
  --warm-base 100k --warm-add 2k --loads "$loads" 2>&1 | sed 's/^/TTFT /'
echo "PROBE ttft exit $?"
echo "HEALTH1 $(health)"
docker logs qwen38-flash-next-tf > "$OUT/serve.log" 2>&1
echo "SOURCES $(grep -a '^\[tensorfold\] [0-9a-f.:]* "' "$OUT/serve.log" | awk '{print $2}' | sort | uniq -c | tr '\n' ' ')"
echo "=== cell C=$C DONE $(date -Is) $((SECONDS - t0)) s gpu $(gpu)"
