#!/usr/bin/env bash
# mutants.sh (spark6): patches/0027's checks and a mutant each, judged by exit code.
# Host: hostmut4.py (the unmutated tree passes both suites, then each mutant must fail its named test).
# GPU (takes ~/work/gpu.lock; called from inside a held lock, drop the flock): gpucheck4.sh runs `tensorfold reuse`
# (the prompt-cache lane's capture) on tensorfold-qwen38:zpr-b4c-stack with the control build mounted, which must pass,
# then with each mutant build, which must fail; it exits 0 only when the control passes and every mutant fails.
set -uo pipefail
cd ~/work/lanes/b4-pack || exit 1
python3 hostmut4.py find-ignores-salt find-replays-inner-state keep-no-whole-upgrade marks-whole-beside-history \
  whole-rules-ignore-can whole-min-zero-taken lanes-no-whole-mark pass-no-whole-keep two-late-keeps sliced-drops-whole \
  host-keep-unsalted host-lookup-unsalted cache-salt-empty-taken victim-long-ignores-short victim-short-frees-any \
  reserve-no-shortroom lookup-no-refusal resumed-no-branch-mark victim-ignores-branched keep-no-shortroom \
  shortroom-ignores-skip || exit 1
flock -o ~/work/gpu.lock timeout 1740 bash gpucheck4.sh reuse e1-replay-stale-logits e2-replay-no-tail
