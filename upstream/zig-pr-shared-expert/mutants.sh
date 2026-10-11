#!/usr/bin/env bash
# mutants.sh (spark6): patches/0028's checks and a mutant each, judged by exit code.
# Host: hostmut4.py (the unmutated tree passes both suites, then each mutant must fail its named test).
# GPU (takes ~/work/gpu.lock; called from inside a held lock, drop the flock): gpucheck4.sh `slot-ld-check` (its own
# slot mutant inside) with the control build, then `boot`: b4boot.sh, the recipe's start.sh serve on
# tensorfold-qwen38:zpr-b4c-stack with this PR's settings and golden replies, with the control build mounted, which
# must pass, then with each mutant build, which must fail; it exits 0 only when the control passes and every mutant
# fails.
set -uo pipefail
cd ~/work/lanes/b4-pack || exit 1
python3 hostmut4.py early-fork-cap-exclusive early-fork-prefill early-fork-zero-forks early-rows-side-ignored \
  early-rows-past-max || exit 1
flock -o ~/work/gpu.lock timeout 1740 bash -c 'bash gpucheck4.sh slot-ld-check && bash gpucheck4.sh boot \
  slot-ld-wrong-slot early-forked-never-cleared'
