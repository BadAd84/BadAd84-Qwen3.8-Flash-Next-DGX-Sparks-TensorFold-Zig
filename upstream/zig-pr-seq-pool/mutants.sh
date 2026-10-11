#!/usr/bin/env bash
# mutants.sh: patches/0016's exactness evidence is GPU-side (lane w3-opus, ~/work/lanes/w3-opus/): golden 6/6 on every
# non-mutant boot, 141/141 bench replies identical across arms (hold 4). Mutants, run with the lane image's
# TF_FLASHNEXT_POOL_MUTANT switch (not in the packaged patch): 3 (the last request's states carried over and prefill's
# reset skipped) golden 3/6 + 18/33 short replies differ = killed (zgold-mut3-c1.json, w3-mut3-c1.log); 1 (the pool's
# own reset skipped) and 2 (the zeroing skipped) no difference: both are backups of prefill's own reset, which the
# patch keeps. Re-running needs the lane image and the GPU lock.
# Review round 1 (2026-10-11), on the fixed stack (~/work/lanes/r1-fix, tf branch `stack`): the round's
# new host tests and a mutant each, judged by exit code (hostmut.py exits 0 only when every one is killed).
python3 ~/work/lanes/r1-fix/hostmut.py count-setting-silently-unset reset-drops-mtp-drafted reset-keeps-recurrent-state || exit 1
# `pool-check` passes on the fixed stack and fails with each mutant binary (gmutants.json):
bash ~/work/lanes/r1-fix/gpucheck.sh pool-check reset-keeps-recurrent-state || exit 1
echo "manual: see the header" >&2
exit 2
