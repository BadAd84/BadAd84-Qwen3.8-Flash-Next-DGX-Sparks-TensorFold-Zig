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
mutant stock-template-always dry zab_rm.sh 'tpl="$HERE/rigmark/metadata-$engine-ours.json"' \
  'tpl="$HERE/rigmark/metadata-$engine-stock.json"'
mutant ours-template-always dry zab_rm.sh '    tpl="$HERE/rigmark/metadata-$engine-stock.json"' \
  '    tpl="$HERE/rigmark/metadata-$engine-ours.json"'
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
# the Python engine (ENGINE=python arms, the python templates, effort_check.py's Python path)
mutant py-ref-is-zig dry zab_rm.sh 'ref=$PY_GOLDEN_REF' 'ref=$GOLDEN_REF'
mutant py-skip-prefill-dropped dry zab_rm.sh 'rm_args="$rm_args --skip-prefill"' 'rm_args="$rm_args"'
mutant py-serve-left-running dry zab_rm.sh 'if [ "$ARM_ENGINE" = python ]; then' 'if false; then'
mutant py-zig-not-stopped dry zab_rm.sh '( cd "$ZIG_RECIPE" && ./stop.sh </dev/null ) 2>&1 | tail -1' ':'
mutant py-kernel-cache-shared dry zab_rm.sh 'env KERNEL_CACHE="$PY_KERNEL_CACHE" "$@"' 'env "$@"'
mutant py-ref-always-rewritten dry zab_rm.sh '[ "$engine" = python ] && [ ! -f "$ref" ] && [ "$(basename' \
  '[ "$engine" = python ] && [ "$(basename'
mutant py-decode-off dry zab_rm.sh 'if [ "$engine" = python ] && [ "$PY_DECODE" = 1 ]; then' 'if false; then'
mutant ttft-knob-ignored dry zab_rm.sh 'if [ "$TTFT" = 1 ]; then' 'if true; then'
mutant decode-sum-dropped dry zab_rm_sum.py '    if d_lines:' '    if False:'
mutant py-ref-from-any-arm dry zab_rm.sh ' && [ "$(basename "$tpl")" = metadata-python-stock.json ] \' ' \'
mutant engine-check-off dry rigmark_meta.py 'if engine != expect.get("engine"):' 'if False:'
mutant kv-check-off dry rigmark_meta.py 'if "kv_dtype" in expect and opt.get("--kv-dtype") != expect["kv_dtype"]:' \
  'if False:'
mutant image-check-off dry rigmark_meta.py 'if "image" in expect and image_id !=' 'if False and image_id !='
mutant env-check-off dry rigmark_meta.py 'if "env" in expect and tf != expect["env"]:' 'if False:'
mutant args-check-off dry rigmark_meta.py 'if "args" in expect and sargs != expect["args"]:' 'if False:'
mutant recipe-args-ignored dry rigmark_meta.py 'and (recipe_args is None or sargs == recipe_args))' 'and True)'
mutant py-revision-unread dry rigmark_meta.py 'return spec, ref.read_text().strip()' 'return spec, "unknown"'
mutant py-health-unread dry rigmark_meta.py 'if "live" not in health and "requests_running" in health:' 'if False:'
mutant effort-live-count-off dry effort_check.py 'if live != p_with["tokens"]:' 'if False:'
mutant effort-python-path-off dry effort_check.py \
  'why = python(port, raw, extra) if engine == "python" else zig(port, raw, extra)' 'why = zig(port, raw, extra)'
if [ "$killed" = "$total" ]; then echo "ALL KILLED $killed / $total"; exit 0; fi
echo "NOT CLEAN: $killed / $total killed"; exit 1
