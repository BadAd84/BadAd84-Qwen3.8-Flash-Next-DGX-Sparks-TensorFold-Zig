#!/usr/bin/env bash
# zarm2.sh LABEL [VAR=VALUE ...]   (spark6, ~/work, detached): restart the Zig server as zarm.sh does, record golden
# replies, then the copy/rewrite replies (zcopy.py, 3 runs) and cold prefill at 8k / 32k / 128k (prefill_fresh.py, a
# seed base new to every boot so no prompt is ever cached). Rows: zp-LABEL.jsonl, zc-LABEL.jsonl; log zarm2-LABEL.log.
set -uo pipefail
LABEL=$1; shift
cd "$HOME/work" || exit 1
exec >> "zarm2-$LABEL.log" 2>&1
echo "=== $LABEL start $(date -Is) env: $*"
( cd ~/qwen-zig && env "$@" ./start.sh restart </dev/null ) | grep -a "answered\|LIVE\|rror\|die"
docker logs qwen38-flash-next-tf 2>&1 | grep -a "^costs: window 1 \|admit\|budget" | head -3
python3 qf_harness.py golden "zgold2-$LABEL.json" | tail -1
python3 zcopy.py "$LABEL" "zc-$LABEL.jsonl" 3
python3 prefill_fresh.py "$LABEL" "zp-$LABEL.jsonl" "$(( 500000 + RANDOM * 64 ))" | grep median
echo "=== ZARM2 $LABEL DONE $(date -Is)"
