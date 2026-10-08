#!/usr/bin/env bash
# zarm.sh LABEL PASSES [VAR=VALUE ...]   (spark6, ~/work, run detached with </dev/null)
# One arm of a Zig-server HTTP A/B: restart the recipe's server with the given TF_FLASHNEXT_*/TENSORFOLD_* variables
# (start.sh passes them into the container; IMAGE=... picks another image), record golden replies, then run
# qf_run.py's decode matrix PASSES times. /metrics' rounds/drafted/accepted are read around each pass.
# Rows: zab-LABEL.jsonl; golden: zgold-LABEL.json; log: zab-LABEL.log.
set -uo pipefail
LABEL=$1; PASSES=$2; shift 2
cd "$HOME/work" || exit 1
exec > "zab-$LABEL.log" 2>&1
rm -f "zab-$LABEL.jsonl"
metric() { curl -s -m 5 http://127.0.0.1:8888/metrics | awk -v k="tensorfold:$1" '$1==k {print $2}'; }
echo "=== $LABEL start $(date -Is) env: $*"
( cd ~/qwen-zig && env "$@" ./start.sh restart </dev/null ) | grep -a "answered\|LIVE\|rror\|die" 
docker inspect qwen38-flash-next-tf --format '{{.Config.Image}} {{range .Config.Env}}{{if or (eq (slice . 0 3) "TF_") (eq (slice . 0 3) "TEN")}}{{.}} {{end}}{{end}}'
docker logs qwen38-flash-next-tf 2>&1 | grep -a "^costs:" | tr '\n' ';' | sed 's/costs: //g'; echo
python3 qf_harness.py golden "zgold-$LABEL.json" | tail -1
for P in $(seq "$PASSES"); do
  r0=$(metric decode_rounds_total); d0=$(metric mtp_drafted_total); a0=$(metric mtp_accepted_total)
  RUNS=1 python3 qf_run.py "$LABEL-p$P" "zab-$LABEL.jsonl" decode
  r1=$(metric decode_rounds_total); d1=$(metric mtp_drafted_total); a1=$(metric mtp_accepted_total)
  echo "=== pass $P $(date +%T): rounds $((r1-r0)) drafted $((d1-d0)) accepted $((a1-a0))"
done
echo "=== ZARM $LABEL DONE $(date -Is)"
