#!/usr/bin/env bash
# mutants.sh (spark6): patches/0021's checks, judged by exit code.
# 1. Host test (CPU, no GPU lock): ~/work/lanes/r3-prpack/mut0021.sh copies the clean stack tree, removes the one
#    line in cuda_lanes.zig prefillStepFn that makes a filling stream wait for the prompt buffers, and requires
#    `zig build test` to FAIL (the new test and the existing sliced-fill test both fail). Exit 0 = mutant killed.
# 2. The cuda_engine.zig half (the deferred resume absorb) needs the GPU: lane r2d-fill's race2.py on the mutant
#    image r2d-fill1m (since removed) gave wrong replies for the concurrent fresh prompt in 2 of 3 rounds with no
#    error (~/work/lanes/r2d-fill/hold3.out); the fix gave 12/12 shas equal to FILL=0. Not re-runnable here.
set -uo pipefail
bash ~/work/lanes/r3-prpack/mut0021.sh
