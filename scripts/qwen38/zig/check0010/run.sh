#!/usr/bin/env bash
# run.sh SRC   (spark6, in ~/work/zsrc-style TensorFold tree SRC with patches/0001-0010 applied and the recipe-patched
# commit 3289c9e in its history): builds check_rows.cu in the Zig image against the patched kernels (NEW) and the
# shipped logsumexp (OLD, from 3289c9e, renamed), runs it, then the mutants: each must make the check FAIL (judged by
# exit code; every mutant's anchor must match exactly once). Exit 0: the check passes and every mutant is killed.
set -uo pipefail
SRC=$(readlink -f "$1"); HERE=$(dirname "$(readlink -f "$0")")
W=$(mktemp -d "$HOME/work/c0010.XXXXXX") || exit 2
cp "$HERE/check_rows.cu" "$W/"
cp "$SRC/zig/kernels/cuda/torch_ops/argmax.cu" "$SRC/zig/kernels/cuda/torch_ops/argmax_order.h" "$W/"
cp "$SRC/zig/kernels/cuda/torch_ops/fn_logsumexp.cu" "$W/lse_new.cu"
git -C "$SRC" show 3289c9e:zig/kernels/cuda/torch_ops/fn_logsumexp.cu | sed 's/tf_fn_lse_/old_lse_/g; s/tf_fn_logsumexp/old_logsumexp/g' > "$W/lse_old.cu"
build_run() {  # $1: the lse source to test as NEW
  docker run --rm --gpus all -v "$W":/w -w /w --entrypoint bash tensorfold-qwen38:zig-db28187 -c \
    "nvcc -O2 -arch=sm_121 -rdc=true --fmad=false -o check check_rows.cu argmax.cu $1 lse_old.cu >/dev/null && ./check" | tail -1
  return "${PIPESTATUS[0]}"
}
fail=0
build_run lse_new.cu; rc=$?
[[ $rc == 0 ]] || { echo "the check FAILS on the patch itself (exit $rc)"; fail=1; }
mutant() {  # $1 name, $2 sed expression applied to lse_new.cu; the anchor must occur once
  local n; n=$(grep -cF -- "$3" "$W/lse_new.cu")
  [[ "$n" == 1 ]] || { echo "mutant $1: anchor matched $n times"; fail=1; return; }
  sed "$2" "$W/lse_new.cu" > "$W/lse_mut.cu"
  if build_run lse_mut.cu >/dev/null; then echo "mutant $1: SURVIVED"; fail=1; else echo "mutant $1: killed"; fi
}
mutant no-tail  's|for (; i < n; i += step) {|for (; false; i += step) {|'  'for (; i < n; i += step) {'
mutant unroll3  's|for (int u = 0; u < 4; ++u) m = |for (int u = 0; u < 3; ++u) m = |'  'for (int u = 0; u < 4; ++u) m = '
mutant bound    's|for (; i + 3 \* step < n; i += 4 \* step) {|for (; i + 2 * step < n; i += 4 * step) {|'  'for (; i + 3 * step < n; i += 4 * step) {'
rm -rf "$W"
exit $fail
