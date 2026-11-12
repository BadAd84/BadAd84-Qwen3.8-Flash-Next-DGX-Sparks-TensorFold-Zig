#!/usr/bin/env bash
# mxk.sh - the kernel table with the read-outs in MXFP8, behind mx.sh: gmk21 is gm21 with the diagnostic logs.
# HOLD2 parks stage 3c's decode arms until this is through.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f MX-DONE ] && break; sleep 20; done
bash ./build_rung.sh gmk21 rungs/gmk21.patch > mxk.build.log 2>&1
K="TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1"
bash ./profile_round.sh gmk21 rungs/gmk21.patch "kernmx:$K TF_FLASHNEXT_HC_MXFP8=1" "logmx:TF_FLASHNEXT_HC_MXFP8=1" > mxk.log 2>&1
: > mxk.full.log
for a in kernmx logmx; do
  echo "=== ${a}: every log line" >> mxk.full.log
  grep -a "^round log:\|^kernel log:" "bench/rl-gmk21-$a/c1/logs.txt" >> mxk.full.log
done
rm -f HOLD2
touch MXK-DONE
