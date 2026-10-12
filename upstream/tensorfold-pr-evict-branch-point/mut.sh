#!/usr/bin/env bash
# mut.sh TREE LIST (spark6, ~/work/lanes/tfevict): each line of LIST is `name<TAB>file<TAB>test-name<TAB>old<TAB>new` (\n escapes in
# old/new). Each mutant is TREE copied to m/NAME with one replacement (its anchor must match exactly once), host-tested by
# t.sh. KILLED only when t.sh exits non-zero AND a test whose name contains test-name FAILS in e/NAME*.log (a compile
# error is ERROR, not a kill). One line per mutant on stdout; exit 0 only if every mutant is KILLED.
set -uo pipefail
L=$HOME/work/lanes/tfevict
cd "$L" || exit 1
T=$1
bad=0
while IFS=$'\t' read -r name file want old new; do
  [ -z "$name" ] && continue
  M=$L/m/$name
  rm -rf "$M" && mkdir -p "$M" || exit 1
  tar -C "$T" --exclude=.git --exclude=zig-out --exclude=.zig-cache -cf - . | tar -x -C "$M" || exit 1
  if ! python3 "$L/subst.py" "$M/$file" "$old" "$new"; then echo "MUTANT $name ERROR: anchor"; bad=1; continue; fi
  bash t.sh "$M" "mut-$name" > /dev/null 2>&1
  rc=$?
  logs="e/mut-$name.log e/mut-$name.seam.log"
  if grep -aqE "error: .*(error|unable to|expected type)|: error: " $logs && ! grep -aqE "tests passed|passed;" $logs; then
    echo "MUTANT $name ERROR: does not compile"; bad=1
  elif [ "$rc" = 0 ]; then
    echo "MUTANT $name SURVIVED: $(tail -1 t.log)"; bad=1
  elif grep -aE "FAIL|error: '" $logs | grep -aqF "$want"; then
    echo "MUTANT $name KILLED (exit $rc) by: $(grep -aE "^error: '|FAIL" $logs | grep -aF "$want" | head -1 | cut -c1-160)"
  elif grep -aB1 "^FAIL" $logs | grep -aqF "$want"; then
    echo "MUTANT $name KILLED (exit $rc) by: $want"
  else
    echo "MUTANT $name KILLED-OTHER (exit $rc), not by $want: $(grep -aE "^error: '|FAIL" $logs | head -2 | tr '\n' ' ' | cut -c1-200)"; bad=1
  fi
  rm -rf "$M"
done < "$2"
exit $bad
