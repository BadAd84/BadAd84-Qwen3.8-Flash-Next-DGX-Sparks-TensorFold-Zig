#!/usr/bin/env bash
# halfk.sh - the lane's half tiles (32 output columns a block, the same sums) on the hyper-connection UP read-out.
# The kernel table has UP [10240, 320] at 71 GB/s in 160 blocks of 64 columns, half the rate of the kernels beside
# it; the lane takes half tiles only below 96 blocks. TF_FLASHNEXT_HALF_BELOW=161 moves UP (160 blocks) onto them
# and nothing larger; 400 moves the mixers' widest projections too. gmh21 is gmk21 plus that name for the
# threshold. Runs behind mxk.sh, holding stage 3c's decode arms.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do [ -f MX-DONE ] && break; sleep 20; done
touch HOLD
for i in $(seq 1 900); do [ -f MXK-DONE ] && break; sleep 20; done
bash ./build_rung.sh gmh21 rungs/gmh21.patch > halfk.build.log 2>&1
K="TF_FLASHNEXT_WINDOW_GRAPH=0 TF_FLASHNEXT_KERNEL_LOG=1"
bash ./profile_round.sh gmh21 rungs/gmh21.patch "kern161:$K TF_FLASHNEXT_HALF_BELOW=161" "kern400:$K TF_FLASHNEXT_HALF_BELOW=400" > halfk.kern.log 2>&1
: > halfk.full.log
for a in kern161 kern400; do
  echo "=== ${a}: every log line" >> halfk.full.log
  grep -a "^round log:\|^kernel log:" "bench/rl-gmh21-$a/c1/logs.txt" >> halfk.full.log
done
export HOLD_FILE=none NORESTORE=1
KV_DTYPE=bf16 CONTEXT=131072 IMG=tensorfold-qwen38:gmh21 bash ./patcheval.sh \
  "h1warm:" "h1off:" "h1on161:TF_FLASHNEXT_HALF_BELOW=161" "h1on400:TF_FLASHNEXT_HALF_BELOW=400" \
  "h1off2:" "h1on161b:TF_FLASHNEXT_HALF_BELOW=161" "h1on400b:TF_FLASHNEXT_HALF_BELOW=400" > halfk.log 2>&1
rm -f HOLD
touch HALFK-DONE
