#!/usr/bin/env bash
# apply.sh [--check] TREE - upstream PR #2815's one commit onto a TensorFold v1.2.6 tree (pristine, or with any
# prefix of patches/1.2.6 applied). --check writes nothing.
set -euo pipefail
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=${1:?usage: apply.sh [--check] TREE}
HERE=$(cd "$(dirname "$0")" && pwd)
( cd "$HERE" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: the patch does not match SHA256SUMS"; exit 2; }
cd "$TREE"
for p in "$HERE"/[0-9]*.patch; do
  if [ "$check" = 1 ]; then git apply --check --whitespace=nowarn "$p"; else git apply --whitespace=nowarn "$p"; fi
done
[ "$check" = 1 ] && echo "apply.sh: applies (nothing written)" || echo "apply.sh: applied"
