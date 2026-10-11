#!/usr/bin/env bash
# mutants.sh (spark6): patches/0026's checks and a mutant each, judged by exit code.
# Host: hostmut4.py (the unmutated tree passes both suites, then the mutant must fail the named test).
# GPU (takes ~/work/gpu.lock; called from inside a held lock, drop the flock): gpucheck4.sh runs `tensorfold
# first-token-check` on tensorfold-qwen38:zpr-b4c-stack with the control build (the unmutated b4 tree, built as the
# mutants are) mounted, which must pass, then with each mutant build (gmutbuild4.py / gmutants4.json), which must
# fail; it exits 0 only when the control passes and every mutant fails.
set -uo pipefail
cd ~/work/lanes/b4-pack || exit 1
python3 hostmut4.py switch-other-value-is-on || exit 1
flock -o ~/work/gpu.lock timeout 1740 bash gpucheck4.sh first-token-check early-draw-before-logits-copy \
  head-skip-before-layer ngram-late-after-ple
