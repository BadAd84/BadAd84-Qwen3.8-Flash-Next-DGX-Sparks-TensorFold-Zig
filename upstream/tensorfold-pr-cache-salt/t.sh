#!/usr/bin/env bash
# t.sh REF|DIR NAME (spark6, ~/work/lanes/tfevict): host tests of TensorFold ref REF or tree DIR (copied to e/NAME):
# `zig build test` and zig/tests/server/zig_test.sh, in the base image, no GPU, no network.
# Logs e/NAME.log, e/NAME.seam.log; one line appended to t.log. Exit 0 only if both suites exit 0.
set -uo pipefail
L=$HOME/work/lanes/tfevict
cd "$L" || exit 1
source ~/qwen-zig/scripts/config.sh
mkdir -p "$L/e" "$L/zcache"
M=$L/e/$2
docker run --rm --network none -v "$L/e:/e" --entrypoint rm "$BASE_IMAGE" -rf "/e/$2" 2>/dev/null
mkdir -p "$M" || exit 3
if [ -d "$1" ]; then tar -C "$1" --exclude=.git --exclude=zig-out --exclude=.zig-cache -cf - . | tar -x -C "$M" || exit 3
else git -C "$L/tf" archive "$1" | tar -x -C "$M" || exit 3; fi
run() {
  docker run --rm --network none -v "$M:/tf" -v "$HOME/work/lanes/w2-fable/zig-toolchain:/opt/zig:ro" \
    -v "$L/zcache:/root/.cache/zig" -w /tf "$BASE_IMAGE" bash -c "$1"
}
run "/opt/zig/zig build test --summary all" > "$L/e/$2.log" 2>&1
rc=$?
run "ZIG=/opt/zig/zig bash zig/tests/server/zig_test.sh" > "$L/e/$2.seam.log" 2>&1
rs=$?
echo "$2 exit $rc $(grep -a "Build Summary" "$L/e/$2.log" | tail -1) | seam exit $rs $(grep -aE "passed|failed" "$L/e/$2.seam.log" | tr '\n' ' ')" >> "$L/t.log"
tail -1 "$L/t.log"
[ "$rc" = 0 ] && [ "$rs" = 0 ]
