#!/bin/bash
# queue.sh: the v1.1.4-stock vs ours parity matrix at 1/2/4/6/8 streams, one fresh boot per cell, arm order
# alternating per level (ABBA), the whole run under the box's GPU lock. Stop the container at the end.
# Run detached: (setsid nohup ./queue.sh > queue.log 2>&1 < /dev/null &). Stop sparkDash first (fleet rule).
set -u
cd ~/work/lanes/par114 || exit 1
trap '( cd ~/qwen-zig && ./stop.sh ) 2>&1 | tail -1; echo "=== queue exit $(date -Is)"; touch ~/work/lanes/par114/DONE' EXIT
exec 9>~/work/gpu.lock
flock 9 || exit 1
i=0
for C in 1 2 4 6 8; do
  if (( i % 2 == 0 )); then order="stock ours"; else order="ours stock"; fi
  for ARM in $order; do
    echo "=== cell $ARM C=$C $(date -Is)"
    bash ./arm.sh "$ARM" "$C"
    echo "cell rc=$? $(grep -aE '^BOOT seconds|^GOLD exit|^PROBE' runs/$ARM-c$C/arm.log | tr '\n' ' ')"
  done
  i=$((i + 1))
done
