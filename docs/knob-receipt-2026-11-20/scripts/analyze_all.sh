#!/usr/bin/env bash
# analyze_all.sh [window...] - parse every window that has run data, write its analysis, and print the rerun plan
# each one needs. Run on spark6 after the windows (or from the laptop over the fetched box/ copy).
set -u
BOX=${BOX:-$HOME/work/KnobTest}
cd "$BOX" || exit 1
wins=${*:-"w1 w2 w3"}
for w in $wins; do
  d=out/$w
  if [ ! -d "$d" ]; then echo "$w: no directory"; continue; fi
  arms=$(ls "$d" 2>/dev/null | grep -v run.log | wc -l)
  if ! grep -qa "RUN-DONE" "$d/run.log" 2>/dev/null; then echo "$w: INCOMPLETE ($arms arm dirs so far)"; fi
  if [ ! -f "$d/M1/a/boot_time.txt" ] && [ ! -f "$d/M1/d/boot_time.txt" ]; then echo "$w: base arm not booted"; continue; fi
  python3 scripts/analyze_knobs.py "$d" --base M1,M2 --window "$w" --write > "out/$w/analyze.out" 2>&1
  rc=$?
  echo "$w: analyze rc $rc"
  if [ "$rc" = 0 ]; then
    python3 scripts/rerun_plan.py "$d" --plan "plans/$w.tsv" --window "$w" --write
    grep -E "^(conc_t0|openai_t0|a/|b/|p/|d/|TTFT|RESUME)" "out/$w/analyze.out" | head -12
  else
    tail -3 "out/$w/analyze.out"
  fi
done
