#!/usr/bin/env bash
# reseat.sh TREE - re-seat patches/1.2.6 on the TensorFold commit TREE has checked out, one patch at a time with
# three-way applies. Stops at the first patch that leaves a conflict and lists the files; a patch that merges is
# staged so the next one sees it. Run it sourced: ( set -- TREE; . reseat.sh ). START=N resumes at patch N after
# the conflicts of patch N-1 were resolved and staged by hand.
TREE=${1:?worktree at the new base}
REPO=/c/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig
cd "$TREE" || return 1 2>/dev/null || exit 1
i=0
for p in "$REPO"/patches/1.2.6/[0-9]*.patch; do
  i=$((i+1)); [ "$i" -lt "${START:-1}" ] && continue
  b=$(basename "$p")
  git apply --3way --whitespace=nowarn "$(cygpath -m "$p")" > /tmp/reseat.txt 2>&1
  rc=$?
  u=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
  clean=$(grep -c "^Applied patch .* cleanly" /tmp/reseat.txt)
  merged=$(grep -c "^Applied patch .* with conflicts\|^U " /tmp/reseat.txt)
  if [ -n "$u" ] || [ "$rc" != 0 ]; then
    echo "$b: STOPS (rc $rc): conflicts in: $u"
    grep "^error:" /tmp/reseat.txt | head -5 | cut -c1-160
    return 3 2>/dev/null || exit 3
  fi
  echo "$b: seated ($clean files clean, $(grep -c 'Falling back to 3-way merge\|Performing three-way merge' /tmp/reseat.txt) by three-way)"
done
echo "reseat: all $i seated on $(git rev-parse --short HEAD)"
