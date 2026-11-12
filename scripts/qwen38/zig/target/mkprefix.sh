#!/usr/bin/env bash
# mkprefix.sh TREE N [EXTRA.patch ...] - a scratch TensorFold worktree at pristine 6e9af930 with the first N patches
# of patches/1.2.6 applied, then any extra patches in order. With OUT=file, also writes the cumulative patch (the
# form build_rung.sh takes). Run it sourced: ( set -- TREE N ...; . mkprefix.sh )
TREE=${1:?scratch worktree}; N=${2:?how many patches of the series}; shift 2
REPO=/c/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig
cd "$TREE" || return 1 2>/dev/null || exit 1
[ "$(git rev-parse HEAD)" = 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 ] || { echo "mkprefix: $TREE is not at the base"; return 1 2>/dev/null || exit 1; }
git reset -q && git checkout -q -- . && git clean -qfd
i=0
for p in "$REPO"/patches/1.2.6/[0-9]*.patch; do
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
