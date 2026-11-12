#!/usr/bin/env bash
# mx.sh - the hyper-connection matrices re-coded to MXFP8 at load (TF_FLASHNEXT_HC_MXFP8=1), on the repaired
# accepted rung. The kernel table puts 15.4 ms of a 62.6 ms round in the BF16 read-outs (1.32 GB walked a round);
# MXFP8 halves the bytes. It is not exact: the replies are compared with stock's and counted.
# gm21 is g21 plus the lever. Off, it must be g21: same replies, same speed. Runs between stage 3c's cold prompt
# arms and its decode arms (HOLD parks the latter), then lets them go.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 900); do grep -aq "decode and golden" stage3c.outer.log 2>/dev/null && break; sleep 20; done
bash ./build_rung.sh gm21 rungs/gm21.patch > mx.build.log 2>&1
ON="TF_FLASHNEXT_HC_MXFP8=1"
export HOLD_FILE=none NORESTORE=1
KV_DTYPE=bf16 CONTEXT=131072 IMG=tensorfold-qwen38:gm21 bash ./patcheval.sh \
  "m1warm:" "m1off:" "m1on:$ON" "m1off2:" "m1on2:$ON" > mx.log 2>&1
bash ./prefill_arm.sh "mxoff:gm21:" "mxon:gm21:$ON" > mx.pf.log 2>&1
rm -f HOLD
touch MX-DONE
