#!/usr/bin/env bash
# mkrung.sh K [OUT.tgz] - build the rung tree for old patches 0001..K in the scratch worktree tf-lc:
# pristine 6e9af930, the old patches in order, 0012b right after 0012 (kv8 leaves the draft head bf16), the tile
# kernel fields from the old tail once 0023 is in, then overlay.py's repairs. Prints the applied count; with OUT,
# writes the tree as a tarball for a compile on the box.
set -uo pipefail
K=${1:?last old patch number}
OUT=${2:-}
REPO=/c/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig
P=$REPO/patches/1.2.6
T=/c/Users/Adam/Gitea/tf-lc
cd "$T" || exit 1
git checkout -q -- . && git clean -qfd
n=0
for p in "$P"/*.patch; do
  b=$(basename "$p"); num=${b%%-*}
  [ "$num" \> "$K" ] && break
  case "$num" in 0030) continue ;; esac   # the old tail is redistributed, never applied whole
  git apply --whitespace=nowarn "$(cygpath -m "$p")" || { echo "rung $K: APPLY FAIL at $num"; exit 2; }
  n=$((n+1))
  if [ "$num" = 0012 ]; then
    git apply --whitespace=nowarn "$(cygpath -m "$REPO/work/rungfix/0012b-flashnext-kv8-leaves-the-draft-head-bf16.patch")" || { echo "rung $K: 0012b FAIL"; exit 2; }
  fi
  if [ "$num" = 0023 ]; then
    git apply --whitespace=nowarn "$(cygpath -m "$REPO/work/rungfix/tail-tile-kernels.patch")" || { echo "rung $K: tile fields FAIL"; exit 2; }
  fi
done
python "$(cygpath -m "$REPO/scripts/qwen38/zig/target/overlay.py")" "$((10#$K))" "$(cygpath -m "$T")" "$(cygpath -m "$P")" || exit 3
echo "rung $K: $n old patches, $(git status -s | wc -l) paths changed, residue lines: $(git grep -cE '^[0-9]+: @(both|ours|theirs)' -- zig CHANGELOG.md 2>/dev/null | wc -l)"
if [ -n "$OUT" ]; then tar czf "$(cygpath -m "$OUT")" --exclude=.git . && echo "rung $K: tree -> $OUT"; fi
