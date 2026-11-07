#!/usr/bin/env bash
# abq.sh: stock upstream v1.2.4 (up124) against the same tree with the copy re-sync and the shared-round copy ramp
# ported on (cw124), one fresh boot a cell, ABBA per stream level so a slow drift cancels. The serve and sparkDash
# are stopped first and restored on the way out, whatever happens.
set -uo pipefail
L=$HOME/work/lanes/par114
export RUNS_DIR=$L/runs2
mkdir -p "$RUNS_DIR"
PROX="root@proxmox.ots-int.net"

restore() {
  echo "=== restore $(date -Is)"
  ( cd ~/qwen-zig && ./stop.sh ) 2>&1 | tail -2
  for p in $(pgrep -f "qwen6-gpu-lock-holder" | grep -vw $$); do kill "$p"; done
  sleep 10
  setsid nohup "$HOME/qwen6-start.sh" > "$HOME/qwen6-boot.log" 2>&1 < /dev/null &
  for _ in $(seq 1 90); do
    sleep 10
    curl -sf -m 5 -o /dev/null http://127.0.0.1:8888/health && break
  done
  echo "HEALTH $(curl -s -m 5 http://127.0.0.1:8888/health | cut -c1-200)"
  echo "sparkdash: restarted by the session that launched this run (spark6 cannot reach proxmox)"
}
trap restore EXIT

echo "=== abq start $(date -Is)"
echo "sparkdash: stopped by the session that launched this run"
( cd ~/qwen-zig && ./stop.sh ) 2>&1 | tail -3
for p in $(pgrep -f "qwen6-gpu-lock-holder" | grep -vw $$); do kill "$p"; done
sleep 15
nvidia-smi --query-gpu=memory.used,temperature.gpu --format=csv,noheader

for cell in "up124 1" "cw124 1" "cw124 2" "up124 2" "up124 4" "cw124 4" "cw124 6" "up124 6"; do
  set -- $cell
  echo "--- cell $1 c$2 start $(date -Is)"
  bash "$L/arm.sh" "$1" "$2"
  echo "--- cell $1 c$2 rc=$? $(date -Is)"
  if [ "$1" = up124 ] && [ ! -f "$L/zgold-up124.json" ] && [ -f "$RUNS_DIR/up124-c$2/zgold.json" ]; then
    cp "$RUNS_DIR/up124-c$2/zgold.json" "$L/zgold-up124.json"
    echo "recorded up124's own golden replies as the cw124 reference"
  fi
  if [ "$2" = 4 ]; then
    ( cd "$HOME/work/lanes/rpr/recipe" && API_URL=http://127.0.0.1:8888 PORT=8888 \
      python3 tools/exact.py --max-tokens 160 --prompts 6 ) 2>&1 | sed "s/^/EXACT-$1 /" | tail -20
    echo "exact rc=$? for $1"
  fi
  tail -40 "$RUNS_DIR/$1-c$2/arm.log" | grep -aE "GOLD|GOLDUP|COPY|EDITS|BOOTLOG copy|=== " | head -30
done
echo "=== abq matrix done $(date -Is)"
