#!/usr/bin/env bash
# merge1.sh: apply the winning lane patches in order onto a fresh clone of branch `up` (recipe + 0010 + 0011),
# with 0104 (cost log) first, using 3-way merges; report each step.
set -uo pipefail
M=~/work/merge; rm -rf "$M"; mkdir -p "$M"
git clone -q ~/work/zsrc/tf "$M/tf" && cd "$M/tf" && git checkout -q up || exit 1
git -c user.name=m -c user.email=m commit -q --allow-empty -m base
for p in ~/work/zbuild/ots0104-log-costs.patch ~/work/lanes/w1-fable/ngram-host.patch \
         ~/work/lanes/w2-fable/w2-wide-window.patch ~/work/lanes/w4-fable/batch-draws-v2.patch; do
  echo "== $(basename "$p")"
  if git apply --3way "$p" 2>&1 | tail -4; then :; fi
  if git diff --name-only --diff-filter=U | grep -q .; then echo "CONFLICTS:"; git diff --name-only --diff-filter=U; exit 2; fi
  git add -A && git -c user.name=m -c user.email=m commit -qm "$(basename "$p")" && echo "applied"
done
grep -c "COPY_RESYNC\|RESYNC" zig/src/core/lanes/*.zig zig/src/core/*.zig 2>/dev/null | grep -v ":0"
git log --oneline | head -6
