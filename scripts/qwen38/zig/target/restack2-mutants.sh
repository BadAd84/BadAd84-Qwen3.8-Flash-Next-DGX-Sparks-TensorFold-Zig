#!/usr/bin/env bash
# restack2-mutants.sh - spark6: do 0004's new slot test and its guards fail when the fix is taken back?
# The package applied to pristine 964174ea05, `zig build test-cuda-host -j8` in a clean shell once as is, then once per
# mutant (each anchor must match exactly once, the file is restored after): M1 the old slot rounding (`@max(1, mib << 20)
# / @sizeOf(Slot)`, 0 MiB gives 0 slots), M2 create without its `slot_count < 2` guard, M3 the MiB count shifted
# instead of saturated. A mutant is killed when the run reports a failure of 0004's slot test. Prints summary.txt.
set -u
R=$HOME/work/restack2m
BASE=964174ea05879e6dde1de1198a3aae3ef8b46a3b
F=zig/src/families/flashnext/cuda_ple_cache.zig
cd "$R" || exit 1
trap 'rm -rf "$R/head" "$R/zig" "$R/gcache" "$R/mirror"; date -u +%T > "$R/DONE"' EXIT
eval "$(bash -c 'source ~/qwen-zig/scripts/config.sh >/dev/null 2>&1; printf "ZIG_VERSION=%q ZIG_SHA256=%q\n" "$ZIG_VERSION" "$ZIG_SHA256"')"
curl -fsSL -o zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" &&
  echo "${ZIG_SHA256}  zig.tar.xz" | sha256sum -c - > /dev/null || { echo "ZIG FAILED" > summary.txt; exit 1; }
top=$(python3 -c 'import tarfile; t = tarfile.open("zig.tar.xz"); n = t.getnames()[0].split("/")[0]; t.extractall("."); print(n)')
rm -f zig.tar.xz && mv "$top" zig
git init -q mirror && git -C mirror fetch -q --depth 1 git://192.168.99.16/up-pr/tf "$BASE" || { echo "FETCH FAILED" > summary.txt; exit 1; }
mkdir -p head && git -C mirror archive "$BASE" | tar -x -C head
( cd head && for p in "$R"/patches/[0-9]*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done ) || { echo "APPLY FAILED" > summary.txt; exit 1; }
cp "head/$F" "$R/orig.zig"
unset_tf=$(env | grep -oE '^(TF_|TENSORFOLD_)[A-Za-z0-9_]+' | sed 's/^/-u /' | tr '\n' ' ')
run() {
  ( cd head && env $unset_tf ZIG_GLOBAL_CACHE_DIR="$R/gcache" "$R/zig/zig" build test-cuda-host -j8 --maxrss 8000000000 > "$R/$1.log" 2>&1 )
  echo "== $1 rc=$? $(grep -E '^Build Summary' "$R/$1.log" | cut -c1-120)"
  grep -oE "^error: '[^']+' (failed|leaked [0-9]+ allocations?)" "$R/$1.log" | sort -u
  grep -cE "address space is a power of two of slots" "$R/$1.log" | sed 's/^/slot-test lines: /'
}
mutate() {
  local name=$1 from=$2 to=$3
  local n; n=$(grep -cF -- "$from" "head/$F")
  [ "$n" = 1 ] || { echo "== $name: anchor matched $n times, not run"; return; }
  python3 -c 'import sys; p, a, b = sys.argv[1:]; s = open(p).read(); open(p, "w").write(s.replace(a, b, 1))' "head/$F" "$from" "$to"
  run "$name"
  cp "$R/orig.zig" "head/$F"
}
{
  echo "zig $("$R/zig/zig" version), $(ls "$R"/patches/[0-9]*.patch | wc -l) patches"
  run unmutated
  mutate M1 "std.math.floorPowerOfTwo(usize, @max(2, bytes / @sizeOf(Slot)))" "std.math.floorPowerOfTwo(usize, @max(1, bytes) / @sizeOf(Slot))"
  mutate M2 "slot_count < 2 or " ""
  mutate M3 "std.math.mul(usize, mib, 1 << 20) catch std.math.maxInt(usize)" "mib << 20"
} > summary.txt 2>&1
