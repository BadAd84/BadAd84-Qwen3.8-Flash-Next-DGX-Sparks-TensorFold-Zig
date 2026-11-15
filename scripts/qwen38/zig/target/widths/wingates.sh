#!/usr/bin/env bash
# wingates.sh - on the Windows side, in work/Int4Port-widths: pr_check against refs/int4port/base, lean base against head (the
# skill's form: the head's checker copied into a detached base worktree), the aarch64 compile steps, atc overlap.
cd "$(dirname "$0")/../Int4Port-widths" || exit 1
O=../Int4Port
python tools/pr_check.py --base refs/int4port/base > $O/g-prcheck.txt 2>&1
echo "PRCHECK rc $? $(tail -2 $O/g-prcheck.txt | tr '\n' ' ')"
git worktree remove --force ../lean-base-Int4Port > /dev/null 2>&1
git worktree add --detach ../lean-base-Int4Port "$(git merge-base HEAD refs/int4port/base)" > /dev/null 2>&1
cp tools/zig/lean_check.py ../lean-base-Int4Port/tools/zig/lean_check.py
(cd ../lean-base-Int4Port && python tools/zig/lean_check.py > ../Int4Port/lean-base.txt 2>&1)
python tools/zig/lean_check.py > $O/lean-head.txt 2>&1
echo "LEAN base $(tail -1 $O/lean-base.txt) | head $(tail -1 $O/lean-head.txt) | $(python tools/zig/lean_new.py $O/lean-base.txt $O/lean-head.txt 2>&1 | tail -1)"
git worktree remove --force ../lean-base-Int4Port
cd ../.. || exit 1
for step in compile-config-server compile-cuda-tests; do
  python work/zigl.py work/Int4Port-widths build $step -Dtarget=aarch64-linux-gnu > work/Int4Port/g-$step.log 2>&1
  echo "AARCH64 $step rc $? $(grep -a -m2 'error:' work/Int4Port/g-$step.log | tr '\n' ' ' | cut -c1-200)"
done
cd work/Int4Port-widths && cmd.exe /c "atc overlap --json" > ../Int4Port/atc-overlap.json 2> ../Int4Port/atc-overlap.err
echo "ATC rc $?"
echo "WINGATES DONE"
