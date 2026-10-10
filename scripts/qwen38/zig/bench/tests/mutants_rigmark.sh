#!/bin/bash
# mutants_rigmark.sh <rigmark clone at the pinned commit>   CPU only: the RigMark side's decisions must each be
# load-bearing. Each mutant is a scratch copy of the bench directory (under $HOME) with ONE anchored replacement (an
# anchor that does not match exactly once is an ERROR, never a pass), run through test_rigmark_dryrun.sh (or, for
# zab_rm_sum.py's missing-verdict branch, test_ttft.py's zab_rm_sum checks); the test must FAIL. Prints KILLED /
# SURVIVED / ERROR per mutant and "ALL KILLED n / n" or "NOT CLEAN"; exit 0 only when every mutant is killed.
set -u
RM=$(cd "${1:?rigmark clone}" && pwd)
HERE=$(cd "$(dirname "$0")" && pwd); BENCH=$(cd "$HERE/.." && pwd); ZIG=$(cd "$BENCH/.." && pwd)
total=0 killed=0
mutant() {   # name test(dry|ttft) file old new
  local d out; total=$((total + 1))
  d=$(mktemp -d "$HOME/mut-rigmark-XXXX") || return
  cp -r "$BENCH" "$d/bench"; cp "$ZIG/zgold_cmp.py" "$d/zgold_cmp.py"
  if ! python3 - "$d/bench/$3" "$4" "$5" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
if s.count(old) != 1:
    sys.exit(1)
open(p, "w").write(s.replace(old, new))
PY
  then echo "ERROR $1: anchor does not match exactly once"; rm -rf "$d"; return; fi
  if [ "$2" = dry ]; then bash "$d/bench/tests/test_rigmark_dryrun.sh" "$RM" > "$d/out" 2>&1
  else python3 -B "$d/bench/tests/test_ttft.py" --scripts-dir "$d/bench" > "$d/out" 2>&1; fi
  local rc=$?
  out=$(grep -m1 '^FAIL' "$d/out")
  if [ "$rc" != 0 ] && [ -n "$out" ]; then echo "KILLED $1: $out"; killed=$((killed + 1))
  elif [ "$rc" = 0 ]; then echo "SURVIVED $1"
  else echo "ERROR $1: the test crashed (exit $rc): $(tail -1 "$d/out")"; fi
  rm -rf "$d"
}
mutant golden-skip-removed dry zab_rm.sh 'if [ "$gold" != 0 ]; then' 'if false; then'
mutant stock-template-always dry zab_rm.sh 'tpl="$HERE/rigmark/metadata-zig-ours.json"' \
  'tpl="$HERE/rigmark/metadata-zig-stock.json"'
mutant patches-dropped dry zab_rm.sh 'RIGMARK_OTS_PATCHES="$patches" bash' 'RIGMARK_OTS_PATCHES="" bash'
mutant stock-check-off dry rigmark_meta.py 'if arm.startswith("stock:") and not is_stock:' 'if False:'
mutant ours-check-off dry rigmark_meta.py 'if arm.startswith("ours:") and is_stock:' 'if False:'
mutant image-env-kept dry rigmark_meta.py '          and baked.get(k) != v}' '          }'
mutant gpu-check-off dry rigmark_meta.py 'if len(cards) != 1 or "GB10" not in cards[0]:' 'if False:'
mutant default-body-glm dry rigmark_run.sh "EXTRA=\${4:-'{\"reasoning_effort\": \"low\"}'}" \
  "EXTRA=\${4:-'{\"chat_template_kwargs\": {\"reasoning_effort\": \"low\"}}'}"
mutant sum-diff-ignored dry zab_rm_sum.py 'DIFF (zgold_cmp.py exit {rc})")
            bad += 1' 'DIFF (zgold_cmp.py exit {rc})")'
mutant sum-noverdict-ignored ttft zab_rm_sum.py 'print(f"golden {arm}: NO VERDICT")
            bad += 1' 'print(f"golden {arm}: NO VERDICT")'
if [ "$killed" = "$total" ]; then echo "ALL KILLED $killed / $total"; exit 0; fi
echo "NOT CLEAN: $killed / $total killed"; exit 1
