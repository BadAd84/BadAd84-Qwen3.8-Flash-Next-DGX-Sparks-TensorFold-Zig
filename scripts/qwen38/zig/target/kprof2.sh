#!/usr/bin/env bash
# kprof2.sh - the per-kernel table (the switch is TF_FLASHNEXT_KERNEL_LOG: the recipe forwards only TENSORFOLD_*
# and TF_FLASHNEXT_* into the container, which is why TF_CUDA_KERNEL_LOG printed nothing). Runs between stage 3c's
# builds and its timed arms: prefill_arm.sh waits while HOLD exists.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 600); do grep -aq "cold prompt time" stage3c.outer.log 2>/dev/null && break; sleep 20; done
bash ./build_rung.sh gk21b rungs/gk21b.patch > kprof2.build.log 2>&1
K="TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1"
bash ./profile_round.sh gk21b rungs/gk21b.patch "kern:$K" "kernbf16:$K TF_FLASHNEXT_DRAFT_HEAD=bf16" > kprof2.log 2>&1
STREAMS=4 bash ./profile_round.sh gk21b rungs/gk21b.patch "kern:$K" >> kprof2.log 2>&1
: > kprof2.full.log
for a in kern/c1 kernbf16/c1 kern/c4; do
  echo "=== ${a}: every log line" >> kprof2.full.log
  grep -a "^round log:\|^kernel log:" "bench/rl-gk21b-${a%%/*}/${a##*/}/logs.txt" >> kprof2.full.log
done
rm -f HOLD
touch KPROF2-DONE
