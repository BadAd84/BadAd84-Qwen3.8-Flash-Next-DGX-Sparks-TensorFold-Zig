#!/usr/bin/env bash
# hoststeps.sh REPO PATCH [STEP...] - the head (up/main plus PATCH) rebuilt in WSL and each STEP run as one zig build
# invocation (default: test-cuda-host, test-environment-host, "test test-golden"). Logs: ~/work/tensorfold/widths/.
Z=/home/adam/tools/zig-x86_64-linux-0.17.0/zig
W=/home/adam/work/tensorfold/widths
repo=$1 patch=$2; shift 2
[ $# -gt 0 ] || set -- test-cuda-host test-environment-host "test test-golden"
rm -rf "$W/head" && mkdir -p "$W/head"
git -C "$repo" archive up/main | tar -x -C "$W/head"
cd "$W/head" && git init -q && git apply --whitespace=nowarn "$patch" || { echo "PATCH FAILED"; exit 1; }
for step in "$@"; do
  log="$W/steps-${step// /_}.log"
  # shellcheck disable=SC2086
  timeout 5400 "$Z" build $step --summary all > "$log" 2>&1
  echo "STEP $step rc $? $(tr '\r' '\n' < "$log" | grep -a 'Build Summary' | tail -1)"
done
echo "STEPS DONE $(date -Is)"
