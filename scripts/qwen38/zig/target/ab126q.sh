#!/bin/bash
# ab126q.sh - the stock-v1.2.6 against our-1.2.6-stack matrix on spark6: levels 1/2/4/6, both arms, ABBA order per
# level, one fresh boot per cell, the whole run under the box's GPU lock; then the lever's 8-stream cell alone (no
# base cell exists there: stock at bf16 KV does not fit 8 streams), then the production serve is restored.
# Run detached: (setsid nohup ./ab126q.sh > ab126.log 2>&1 < /dev/null &)
set -u
cd "$HOME/work/target" || exit 1
trap '( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -5; \
       echo "=== production restored $(date -Is)"; touch "$HOME/work/target/AB126-DONE"' EXIT
exec 9>~/work/gpu.lock
flock 9 || exit 1
{
  echo "base $(docker image inspect tensorfold-qwen38:up126 --format '{{.Id}}')"
  echo "lever $(docker image inspect "${LEVER_IMG:-tensorfold-qwen38:stack126}" --format '{{.Id}}')"
  date -Is
} > ab126-manifest.txt
i=0
for C in 1 2 4 6; do
  if (( i % 2 == 0 )); then order="base lever"; else order="lever base"; fi
  for ARM in $order; do
    echo "=== cell $ARM C=$C $(date -Is)"
    bash ./ab126.sh "$ARM" "$C"
    echo "cell $ARM C=$C rc=$? $(grep -aE '^BOOT seconds|^PROBE|BOOT FAILED' "ab126/$ARM-c$C/arm.log" | tr '\n' ' ')"
  done
  i=$((i + 1))
done
echo "=== capacity cell lever C=8 fp8 KV $(date -Is)"
KV_DTYPE=fp8 CONTEXT=262144 bash ./ab126.sh lever 8
echo "capacity lever C=8 rc=$? $(grep -aE '^BOOT seconds|^PROBE|BOOT FAILED' ab126/lever-c8/arm.log | tr '\n' ' ')"
