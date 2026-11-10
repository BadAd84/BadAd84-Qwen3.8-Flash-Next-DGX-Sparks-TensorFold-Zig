#!/bin/bash
# target_queue.sh - the production target matrix on spark6: one fresh boot per concurrency level (1, 2, 4, 6, 8),
# cells in target_arm.sh, then one RigMark run on the last boot, then the production serve is restored and DONE is
# touched on every exit path. The whole run holds the box's GPU lock. Run detached:
#   (setsid nohup ./target_queue.sh > queue.log 2>&1 < /dev/null &)
# Stop sparkDash first (the fleet rule); start it again once DONE appears.
set -u
cd "$HOME/work/target" || exit 1
CID="prod-zmerge8-kfix-$(date -u +%Y%m%dT%H%M%SZ)"
trap '( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -5; \
       echo "=== production restored $(date -Is)"; touch "$HOME/work/target/DONE"' EXIT
exec 9>~/work/gpu.lock
flock 9 || exit 1
{
  echo "comparison $CID"
  docker image inspect tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 --format 'image {{.Id}} {{.Created}}'
  date -Is
} > manifest.txt
for C in 1 2 4 6 8; do
  echo "=== cell C=$C $(date -Is)"
  bash ./target_arm.sh "$C"
  echo "cell C=$C rc=$? $(grep -aE '^BOOT seconds|^GOLD exit|^PROBE|BOOT FAILED' "runs/c$C/arm.log" | tr '\n' ' ')"
done
echo "=== rigmark $CID $(date -Is)"
RIGMARK_DIR="$HOME/rigmark" bash "$HOME/work/bench/rigmark_run.sh" prod-zmerge8-kfix "$CID" \
  "$HOME/work/bench/rigmark/metadata-zig-ours.json" > rigmark.log 2>&1
echo "rigmark rc=$? $(grep -aE '^summary|^exit|^card|^receipt' rigmark.log | tr '\n' ' ')"
