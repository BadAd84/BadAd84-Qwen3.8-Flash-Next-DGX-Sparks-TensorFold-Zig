#!/usr/bin/env bash
# mkseries.sh OUT name:cumulative.patch ... - turn consecutive rung trees into an additive patch series.
# Each argument names a lever and the cumulative patch (against pristine 6e9af930) of the rung that ends with it.
# Patch N is the exact difference between rung N-1 and rung N, so applying 0001..N to a pristine tree reproduces
# rung N. Verified at the end by replaying the whole series and comparing with the last rung's tree.
set -uo pipefail
OUT=${1:?output dir}; shift
T=/c/Users/Adam/Gitea/tf-lc
S=/c/Users/Adam/Gitea/tf-check
mkdir -p "$OUT" && rm -f "$OUT"/*.patch
snap() { # dir cumulative.patch -> tree id on stdout
  ( cd "$1" && git reset -q && git checkout -q -- . && git clean -qfd && git apply --whitespace=nowarn "$2" \
      && git ls-files --others --exclude-standard -z | xargs -0 -r git add -- && git add -u && git write-tree )
}
cd "$T" || exit 1
prev=$(git rev-parse "HEAD^{tree}")
n=0
for spec in "$@"; do
  name=${spec%%:*}; cum=${spec#*:}
  tree=$(snap "$T" "$(cygpath -m "$cum")") || { echo "FAIL applying $cum"; exit 2; }
  n=$((n+1)); f=$(printf '%s/%04d-%s.patch' "$OUT" "$n" "$name")
  # full blob ids: the abbreviation git picks grows with the repository, and a three-way apply reads them
  git diff --binary --full-index "$prev" "$tree" > "$f"
  printf '%04d-%s.patch  %s lines  %s files\n' "$n" "$name" "$(wc -l < "$f")" "$(grep -c '^diff --git' "$f")"
  prev=$tree
done
git reset -q && git checkout -q -- . && git clean -qfd
# replay onto a second pristine worktree and compare the resulting tree id with the last rung's
cd "$S" || exit 1
git reset -q && git checkout -q -- . && git clean -qfd
git checkout -q --detach "$(git -C "$(cygpath -m "$T")" rev-parse HEAD)" || exit 3   # the same pristine commit
for p in "$OUT"/*.patch; do git apply --whitespace=nowarn "$(cygpath -m "$p")" || { echo "REPLAY FAIL at $(basename "$p")"; exit 3; }; done
git ls-files --others --exclude-standard -z | xargs -0 -r git add -- && git add -u
replay=$(git write-tree)
git reset -q && git checkout -q -- . && git clean -qfd
[ "$replay" = "$prev" ] && echo "series replays to the last rung exactly ($prev)" || { echo "MISMATCH: replay $replay, rung $prev"; exit 4; }
