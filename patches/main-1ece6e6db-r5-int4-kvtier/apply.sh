#!/usr/bin/env bash
# apply.sh [--check] TREE - patches/main-1ece6e6db-r5 0001-0020, then this package's patches, in filename order.
# --check proves all of them apply and writes nothing to TREE's files or index: the series is checked with its own
# apply.sh --check, then every patch against a scratch index holding the series' result. Paths are normalised to
# forward slashes, and the series' own apply.sh is run as a program, so a Git Bash run works (there the shell behind
# `bash` is WSL's, which cannot open a C:/ path but can execute one).
set -euo pipefail
BASE=1ece6e6dbbc073582d50738ce8e73e3c3261a73b
slash() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s\n' "$1"; fi; }
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=$(slash "$(cd "${1:?usage: apply.sh [--check] TREE}" && pwd)")
HERE=$(slash "$(cd "$(dirname "$0")" && pwd)")
SERIES=$(slash "$(cd "$HERE/../main-1ece6e6db-r5" && pwd)")
( cd "$HERE" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: this package's patches do not match SHA256SUMS"; exit 2; }
cd "$TREE"
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "apply.sh: $TREE is not at $BASE"; exit 2; }
n=0
if [ "$check" = 1 ]; then
  "$SERIES/apply.sh" --check "$TREE" || exit 1
  idx="$(git rev-parse --git-dir)/int4-kvtier-check.index"
  rm -f "$idx"
  trap 'rm -f "$idx"' EXIT
  export GIT_INDEX_FILE="$idx"
  git read-tree HEAD
  for p in "$SERIES"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
  done
  for p in "$HERE"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply on the series"; exit 1; }
    n=$((n + 1))
  done
  echo "apply.sh: the series and $n INT4 and KV-tier patches apply on $BASE in order (nothing written)"
  exit 0
fi
"$SERIES/apply.sh" "$TREE" || exit 1
for p in "$HERE"/[0-9]*.patch; do
  git apply --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply on the series"; exit 1; }
  n=$((n + 1))
done
echo "apply.sh: the series and $n INT4 and KV-tier patches applied on $BASE"
