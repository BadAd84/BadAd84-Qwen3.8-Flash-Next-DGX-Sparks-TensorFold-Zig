#!/usr/bin/env bash
# apply.sh [--check] TREE - the accepted series (../1.2.7, 0001 to 0015) and then this experimental package, in
# filename order, onto a pristine TensorFold checkout at the base below. --check writes nothing: a scratch index.
set -euo pipefail
BASE=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=${1:?usage: apply.sh [--check] TREE}
HERE=$(cd "$(dirname "$0")" && pwd)
ACCEPTED="$HERE/../1.2.7"
( cd "$ACCEPTED" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: the accepted series does not match its SHA256SUMS"; exit 2; }
( cd "$HERE" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: the patches do not match SHA256SUMS"; exit 2; }
cd "$TREE"
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "apply.sh: $TREE is not at $BASE"; exit 2; }
n=0
if [ "$check" = 1 ]; then
  idx="$(git rev-parse --git-dir)/apply-check.index"
  rm -f "$idx"
  trap 'rm -f "$idx"' EXIT
  export GIT_INDEX_FILE="$idx"
  git read-tree HEAD
  for p in "$ACCEPTED"/[0-9]*.patch "$HERE"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
    n=$((n + 1))
  done
  echo "apply.sh: $n patches apply on $BASE in order (nothing written)"
  exit 0
fi
[ -z "$(git status --porcelain)" ] || { echo "apply.sh: $TREE has local changes"; exit 2; }
for p in "$ACCEPTED"/[0-9]*.patch "$HERE"/[0-9]*.patch; do
  git apply --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
  n=$((n + 1))
done
echo "apply.sh: $n patches applied on $BASE"
