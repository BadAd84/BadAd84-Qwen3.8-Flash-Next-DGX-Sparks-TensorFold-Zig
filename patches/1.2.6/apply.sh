#!/usr/bin/env bash
# apply.sh [--check] TREE - the series onto a pristine TensorFold checkout at the base below, in filename order.
# --check proves the whole series applies and writes nothing to TREE's files or index: it uses a scratch index.
set -euo pipefail
BASE=6e9af930261a88bb28ac0bfb157ce8e57e9eea07
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=${1:?usage: apply.sh [--check] TREE}
HERE=$(cd "$(dirname "$0")" && pwd)
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
  for p in "$HERE"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
    n=$((n + 1))
  done
  echo "apply.sh: $n patches apply on $BASE in order (nothing written)"
  exit 0
fi
[ -z "$(git status --porcelain)" ] || { echo "apply.sh: $TREE has local changes"; exit 2; }
for p in "$HERE"/[0-9]*.patch; do
  git apply --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
  n=$((n + 1))
done
echo "apply.sh: $n patches applied on $BASE"
