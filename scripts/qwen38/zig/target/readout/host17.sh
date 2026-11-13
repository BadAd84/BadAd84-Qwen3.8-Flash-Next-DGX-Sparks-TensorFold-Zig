#!/usr/bin/env bash
# host17.sh [STEP...] - `zig build test-cuda-host` (or the steps given) on pristine v1.2.7, the 15-patch tree and the
# 17-patch tree of patches/1.2.7, on WSL ext4 (a Windows mount gives false failures), one result block a tree.
# Trees under ~/work/<repo>/host17/; run from the repo root inside WSL: bash scripts/qwen38/zig/target/readout/host17.sh
set -u
REPO=$(pwd)
D=$HOME/work/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig/host17
ZIG=$HOME/tools/zig-x86_64-linux-0.17.0/zig
BASE=93a2e93ecebff8aa52b88e58c5dd222516e69c5f
STEPS=("$@"); [ ${#STEPS[@]} -eq 0 ] && STEPS=(test-cuda-host)
mkdir -p "$D" && cd "$D" || exit 1
if [ ! -d base ]; then
  git init -q base && git -C base fetch -q --depth 1 git://192.168.99.16/up-pr/tf "$BASE" && git -C base checkout -q --detach FETCH_HEAD || exit 1
fi
seat() { # dir count
  rm -rf "$1" && cp -a base "$1" || exit 1
  local n=0
  for p in "$REPO"/patches/1.2.7/0*.patch; do
    [ "$n" -ge "$2" ] && break
    git -C "$1" apply --whitespace=nowarn "$p" || { echo "$1: $(basename "$p") does not apply"; exit 1; }
    n=$((n + 1))
  done
  echo "$1: $n patches"
}
seat p15 15
seat p17 17
for t in base p15 p17; do
  for s in "${STEPS[@]}"; do
    t0=$(date +%s)
    ( cd "$t" && "$ZIG" build "$s" ) > "$t-$s.log" 2>&1
    rc=$?
    echo "== $t $s rc=$rc $(( $(date +%s) - t0 ))s $(grep -aoE '[0-9]+ passed[^|]*' "$t-$s.log" | tail -1)"
    grep -aE "error:|failed|FAIL|panic" "$t-$s.log" | grep -av "^ *$" | sort -u | head -12 | cut -c1-240
  done
done
