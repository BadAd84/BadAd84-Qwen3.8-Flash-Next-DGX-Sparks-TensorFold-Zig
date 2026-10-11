#!/usr/bin/env bash
# mutants.sh (spark6): patches/0010's bit-exactness check and its mutants: check_rows.cu runs the patched argmax and
# logsumexp-max launches against the shipped ones on 120 adversarial rows (ties, NaN, +-inf, +-0, tail maxima, widths
# 1 to 248,320), then three mutants of the new loop must each make it fail. Judged by exit code.
# Last run 2026-10-08 23:5x: PASS, 120 rows, 0 differences; mutants no-tail, unroll3, bound: killed.
# Review round 1 (2026-10-11): the kernels at every power-of-two block from 32 to 1024 threads
# (zig/tests/cuda/flashnext/argmax_lse_rows.cu, nvcc as its header says), unmutated and with two mutants of the
# block tree (start at blockDim/4; the right-hand NaN arm dropped); argmaxmut.sh exits 0 only when the test passes
# and both mutants make it fail. GPU: run under the lock.
bash ~/work/lanes/r1-fix/argmaxmut.sh || exit 1
exec ~/work/check0010/run.sh "${1:-$HOME/work/zsrc/tf}"
