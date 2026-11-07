#!/bin/bash
# queue2.sh: after queue.sh's DONE, build stock upstream TensorFold v1.2.4 (no recipe patch) as tensorfold-qwen38:up124
# and run its 1/2/4/6/8 cells (arm.sh up124), one fresh boot each, under the GPU lock. The build waits for DONE so it
# never shares the box with a timed cell; the cells wait for GO2 (touched once sparkDash is stopped again). Stops the
# container and touches DONE2 on every exit path.
set -u
cd ~/work/lanes/par114 || exit 1
UP_REF=267c5af6ad10779c1a3c75823d8e6e64216db376
while [ ! -f DONE ]; do sleep 20; done
echo "=== queue2: matrix done, building up124 at $UP_REF $(date -Is)"
( cd ~/work/merge && ./build-br.sh up124 git://192.168.99.16/up-pr/tf "$UP_REF" > /dev/null 2>&1 ); rc=$?
echo "build rc=$rc $(date -Is) $(docker image inspect tensorfold-qwen38:up124 --format '{{.Id}}' 2>/dev/null | cut -c8-19)"
[ "$rc" = 0 ] || { echo "build failed: $(grep -aE 'error' ~/work/merge/build-up124.log | tail -3)"; touch DONE2; exit 1; }
while [ ! -f GO2 ]; do sleep 20; done
trap '( cd ~/qwen-zig && ./stop.sh ) 2>&1 | tail -1; echo "=== queue2 exit $(date -Is)"; touch ~/work/lanes/par114/DONE2' EXIT
exec 9>~/work/gpu.lock
flock 9 || exit 1
for C in 1 2 4 6 8; do
  echo "=== cell up124 C=$C $(date -Is)"
  bash ./arm.sh up124 "$C"
  echo "cell rc=$? $(grep -aE '^BOOT seconds|^GOLD exit|^PROBE|BOOT FAILED' runs/up124-c$C/arm.log | tr '\n' ' ')"
done
