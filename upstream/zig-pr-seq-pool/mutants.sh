#!/usr/bin/env bash
# mutants.sh: patches/0016's exactness evidence is GPU-side (lane w3-opus, ~/work/lanes/w3-opus/): golden 6/6 on every
# non-mutant boot, 141/141 bench replies identical across arms (hold 4). Mutants, run with the lane image's
# TF_FLASHNEXT_POOL_MUTANT switch (not in the packaged patch): 3 (the last request's states carried over and prefill's
# reset skipped) golden 3/6 + 18/33 short replies differ = killed (zgold-mut3-c1.json, w3-mut3-c1.log); 1 (the pool's
# own reset skipped) and 2 (the zeroing skipped) no difference: both are backups of prefill's own reset, which the
# patch keeps. Re-running needs the lane image and the GPU lock.
echo "manual: see the header" >&2
exit 2
