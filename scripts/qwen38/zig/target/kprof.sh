#!/usr/bin/env bash
# kprof.sh - where a verify window's time goes on the repaired accepted rung: gk21 is g21 with the round log (now
# split into the host's staging and the graph) and a per-kernel time log. Three boots at one stream:
#   log    graphs on (as served): staging against graph, per round
#   eager  graphs off: the same round launched kernel by kernel, to price the graph itself
#   kern   graphs off and every launch waited for: the kernels by time
# The last two are diagnostics: their tok/s is not a speed result.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 1200); do [ -f "${WAIT:-NFIX-DONE}" ] && break; sleep 30; done
bash ./build_rung.sh gk21 rungs/gk21.patch > kprof.build.log 2>&1
bash ./profile_round.sh gk21 rungs/gk21.patch "log:" "eager:TF_FLASHNEXT_WINDOW_GRAPH=0" \
  "kern:TF_FLASHNEXT_WINDOW_GRAPH=0 TF_CUDA_KERNEL_LOG=1" > kprof.log 2>&1
for a in log eager kern; do
  echo "=== $a: every log line" >> kprof.full.log
  grep -a "^round log:\|^kernel log:" "bench/rl-gk21-$a/c1/logs.txt" >> kprof.full.log
done
touch KPROF-DONE
