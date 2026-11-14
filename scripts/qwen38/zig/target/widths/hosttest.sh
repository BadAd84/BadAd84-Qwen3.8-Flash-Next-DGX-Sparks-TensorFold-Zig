#!/usr/bin/env bash
# hosttest.sh REPO PATCH - in WSL: upstream main (up/main in REPO) plus PATCH in ~/work/tensorfold/widths/head, the
# base alone in .../base; test-cuda-host, test-environment-host and test test-golden on the head; the new tests' filter
# on the base with only the tests applied is not built (the module is new); then each mutant in its own copy.
set -u
Z=$HOME/tools/zig-x86_64-linux-0.17.0/zig
W=$HOME/work/tensorfold/widths
REPO=$1
PATCH=$2
mkdir -p "$W"
rm -rf "$W/head" "$W/base" && mkdir -p "$W/head" "$W/base"
git -C "$REPO" archive up/main | tar -x -C "$W/base"
git -C "$REPO" archive up/main | tar -x -C "$W/head"
( cd "$W/head" && git init -q && git apply --whitespace=nowarn "$PATCH" ) || { echo "PATCH FAILED"; exit 1; }
cd "$W/head"
grep -n "test-filter\|test_filter" build.zig | head -3
for step in test-cuda-host test-environment-host "test test-golden"; do
  # shellcheck disable=SC2086
  timeout 5400 "$Z" build $step > "$W/step-${step// /_}.log" 2>&1
  echo "STEP $step rc $? $(grep -a -E 'passed|failed|error:' "$W/step-${step// /_}.log" | tail -2 | tr '\n' ' ' | cut -c1-240)"
done
mutant() { # name file old new
  local n=$1 f=$2 old=$3 new=$4
  rm -rf "$W/mut-$n" && cp -r "$W/head" "$W/mut-$n"
  python3 - "$W/mut-$n/$f" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1:]
s = open(p).read()
assert s.count(old) == 1, (p, s.count(old))
open(p, "w").write(s.replace(old, new))
PY
  ( cd "$W/mut-$n" && timeout 3600 "$Z" build test-cuda-host > "$W/mut-$n.log" 2>&1 )
  echo "MUTANT $n rc $? $(grep -a -E 'expected|failed|FAIL|error:' "$W/mut-$n.log" | head -2 | tr '\n' ' ' | cut -c1-240)"
  rm -rf "$W/mut-$n"
}
F=zig/src/families/flashnext
mutant default-only $F/cuda_widths.zig 'pub const supported = [_]Widths{ default, .{ .top_k = 5, .shared = 2 * wt.moe_w } };' 'pub const supported = [_]Widths{default};'
mutant mlx-any $F/cuda_config.zig 'return if (widthsOf(text).widths.isDefault()) null else "num_experts_per_tok";' 'return null;'
mutant scratch-const $F/cuda_batch_state.zig 'n += cap * z.shared * 6 + cap * dims * 4;' 'n += cap * moe_w * 6 + cap * dims * 4;'
mutant mtp-any $F/cuda_widths.zig 'if (shared_rows != main.shared and shared_rows != wt.moe_w) return null;' 'if (false) return null;'
mutant captured-any $F/cuda_widths.zig '    return w.isDefault();
}' '    _ = w;
    return true;
}'
mutant fixed-top10 $F/cuda_widths.zig 'if (top_k != @as(i64, @intCast(w.top_k))) continue;' 'if (top_k != 10) continue;'
echo "HOSTTEST DONE $(date -Is)"
