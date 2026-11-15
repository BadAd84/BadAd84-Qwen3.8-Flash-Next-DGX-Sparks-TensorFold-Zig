#!/usr/bin/env bash
# apply.sh [--check] TREE - patches/main-964174ea05 0001-0019, then 0016-int4-autoround on top, in filename order.
# --check proves both apply and writes nothing: the series is checked with its own apply.sh --check, and this patch
# against a scratch index holding the series' result.
set -euo pipefail
BASE=964174ea05879e6dde1de1198a3aae3ef8b46a3b
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=${1:?usage: apply.sh [--check] TREE}
HERE=$(cd "$(dirname "$0")" && pwd)
SERIES=$(cd "$HERE/../main-964174ea05" && pwd)
( cd "$HERE" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: the INT4 patch does not match SHA256SUMS"; exit 2; }
cd "$TREE"
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "apply.sh: $TREE is not at $BASE"; exit 2; }
if [ "$check" = 1 ]; then
  "$SERIES/apply.sh" --check "$TREE" || exit 1
  idx="$(git rev-parse --git-dir)/int4-check.index"
  rm -f "$idx"
  trap 'rm -f "$idx"' EXIT
  export GIT_INDEX_FILE="$idx"
  git read-tree HEAD
  for p in "$SERIES"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
  done
  git apply --cached --whitespace=nowarn "$HERE"/[0-9]*.patch || { echo "apply.sh: the INT4 patch does not apply on the series"; exit 1; }
  echo "apply.sh: the series and the INT4 patch apply on $BASE in order (nothing written)"
  exit 0
fi
"$SERIES/apply.sh" "$TREE" || exit 1
for p in "$HERE"/[0-9]*.patch; do
  git apply --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply on the series"; exit 1; }
done
echo "apply.sh: the series and the INT4 patch applied on $BASE"
