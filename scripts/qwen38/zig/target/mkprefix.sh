#!/usr/bin/env bash
# mkprefix.sh TREE N [EXTRA.patch ...] - a scratch TensorFold worktree at the pristine base with the first N patches
# of the series applied, then any extra patches in order. With OUT=file, also writes the cumulative patch (the
# form build_rung.sh takes). BASE (default v1.2.6, 6e9af930) and SERIES (default patches/1.2.6) pick another seat.
# Run it sourced: ( set -- TREE N ...; . mkprefix.sh )
TREE=${1:?scratch worktree}; N=${2:?how many patches of the series}; shift 2
REPO=/c/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig
BASE=${BASE:-6e9af930261a88bb28ac0bfb157ce8e57e9eea07}
SERIES=${SERIES:-$REPO/patches/1.2.6}
cd "$TREE" || return 1 2>/dev/null || exit 1
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "mkprefix: $TREE is not at the base $BASE"; return 1 2>/dev/null || exit 1; }
git reset -q && git checkout -q -- . && git clean -qfd
i=0
for p in "$SERIES"/[0-9]*.patch; do
  [ "$i" -ge "$N" ] && break
  git apply --whitespace=nowarn "$(cygpath -m "$p")" || { echo "mkprefix: $(basename "$p") FAILED"; return 2 2>/dev/null || exit 2; }
  i=$((i+1))
done
for p in "$@"; do
  git apply --whitespace=nowarn "$(cygpath -m "$p")" || { echo "mkprefix: extra $(basename "$p") FAILED"; return 2 2>/dev/null || exit 2; }
done
if [ -n "${OUT:-}" ]; then
  git ls-files --others --exclude-standard -z | xargs -0 -r git add -N -- && git diff --binary > "$(cygpath -m "$OUT")" && git reset -q
fi
echo "mkprefix: $i of the series + $# extra, $(git status -s | wc -l) paths changed${OUT:+, cumulative patch $OUT}"
