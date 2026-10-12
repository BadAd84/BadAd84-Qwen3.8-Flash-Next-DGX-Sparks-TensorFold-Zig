#!/usr/bin/env bash
# gates.sh TREE (spark6, ~/work/lanes/tfevict): main's lean rule (tools/zig/lean_check.py) on TREE against origin/main's
# own findings (only new ones fail), and `zig fmt --check` of the files TREE changes. Exit 0 when both are clean.
set -uo pipefail
L=$HOME/work/lanes/tfevict
cd "$L" || exit 1
source ~/qwen-zig/scripts/config.sh
T=$(readlink -f "$1")
python3 "$L/lean_diff.py" "$L/tf" "$T"
lr=$?
files=$(git -C "$T" status --porcelain | awk '{print $2}' | grep '\.zig$' | tr '\n' ' ')
docker run --rm --network none -v "$T:/tf" -v "$HOME/work/lanes/w2-fable/zig-toolchain:/opt/zig:ro" -w /tf "$BASE_IMAGE" \
  bash -c "/opt/zig/zig fmt --check $files" > "$L/fmt.out" 2>&1
fr=$?
grep -v "NVIDIA\|^$\|=====\|PyTorch\|Container image\|Copyright\|license\|agreements\|found at\|This container\|Various files\|Use the NVIDIA\|GOVERNING\|By pulling\|^NOTE\|insufficient\|shm\|docker\|ulimit\|nvidia" "$L/fmt.out"
echo "lean exit $lr | zig fmt --check exit $fr over: $files"
[ "$lr" = 0 ] && [ "$fr" = 0 ]
