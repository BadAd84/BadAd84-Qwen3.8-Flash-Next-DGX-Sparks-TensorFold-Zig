#!/usr/bin/env bash
# restack2-host.sh - spark6 (native aarch64): `zig build test-cuda-host -j8` on pristine 964174ea05 (base) and on the
# same tree with ~/work/restack2/host/patches applied (head), in two environments each:
#   clean: no TF_ or TENSORFOLD_ variable at all (what upstream's CI sees)
#   prod : ~/qwen-zig/scripts/config.sh's exports, the serve's levers (what a shell that sourced it sees)
# The toolchain is config.sh's Zig, sha-checked, but its values are read in a subshell: sourcing config.sh into the
# build's own environment is what put TF_FLASHNEXT_GATHER_READ=pread into the first spark6 host run.
# Each run has its own local cache (--cache-dir), so a test that passed in one environment is run again in the other.
# Writes summary.txt (failing tests by name, a run each) and DONE.
set -u
R=$HOME/work/restack2/host
BASE=964174ea05879e6dde1de1198a3aae3ef8b46a3b
cd "$R" || exit 1
rm -f DONE summary.txt
trap 'rm -rf "$R/base" "$R/head" "$R/zig" "$R/gcache" "$R/mirror"; date -u +%T > "$R/DONE"' EXIT
eval "$(bash -c 'source ~/qwen-zig/scripts/config.sh >/dev/null 2>&1; printf "ZIG_VERSION=%q ZIG_SHA256=%q\n" "$ZIG_VERSION" "$ZIG_SHA256"')"
curl -fsSL -o zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" &&
  echo "${ZIG_SHA256}  zig.tar.xz" | sha256sum -c - > /dev/null || { echo "ZIG FAILED" > summary.txt; exit 1; }
top=$(python3 -c 'import tarfile; t = tarfile.open("zig.tar.xz"); n = t.getnames()[0].split("/")[0]; t.extractall("."); print(n)')
rm -f zig.tar.xz && mv "$top" zig
echo "zig $("$R/zig/zig" version) (sha256 $ZIG_SHA256), umask $(umask)" > summary.txt
git init -q mirror && git -C mirror fetch -q --depth 1 git://192.168.99.16/up-pr/tf "$BASE" ||
  { echo "FETCH FAILED" >> summary.txt; exit 1; }
for side in base head; do mkdir -p "$side" && git -C mirror archive "$BASE" | tar -x -C "$side"; done
( cd head && git init -q && for p in "$R"/patches/[0-9]*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done ) ||
  { echo "APPLY FAILED" >> summary.txt; exit 1; }
echo "head: $(ls "$R"/patches/[0-9]*.patch | wc -l) patches, sha256 of the series $(cat "$R"/patches/[0-9]*.patch | sha256sum | cut -c1-16)" >> summary.txt
unset_tf=$(env | grep -oE '^(TF_|TENSORFOLD_)[A-Za-z0-9_]+' | sed 's/^/-u /' | tr '\n' ' ')
for run in base:clean head:clean head:prod base:prod; do
  side=${run%%:*}; envname=${run##*:}
  t0=$(date +%s)
  if [ "$envname" = clean ]; then
    ( cd "$side" && env $unset_tf ZIG_GLOBAL_CACHE_DIR="$R/gcache" "$R/zig/zig" build test-cuda-host -j8 \
        --maxrss 8000000000 --cache-dir ".zig-cache-$envname" > "$R/$side-$envname.log" 2>&1 )
  else
    ( cd "$side" && source ~/qwen-zig/scripts/config.sh > /dev/null 2>&1 &&
      echo "prod env: $(env | grep -cE '^(TF_|TENSORFOLD_)') TF_/TENSORFOLD_ variables, $(env | grep -E '^TF_FLASHNEXT_GATHER_READ=')" > "$R/$side-$envname.env" &&
      ZIG_GLOBAL_CACHE_DIR="$R/gcache" "$R/zig/zig" build test-cuda-host -j8 \
        --maxrss 8000000000 --cache-dir ".zig-cache-$envname" > "$R/$side-$envname.log" 2>&1 )
  fi
  rc=$?
  {
    echo "== $side $envname rc=$rc $(( $(date +%s) - t0 ))s $(cat "$R/$side-$envname.env" 2>/dev/null)"
    grep -E '^Build Summary' "$R/$side-$envname.log"
    grep -oE "^error: '[^']+' (failed|leaked [0-9]+ allocations?)" "$R/$side-$envname.log" | sort -u
    grep -cE '^error: ' "$R/$side-$envname.log" | sed 's/^/error lines: /'
  } >> summary.txt
done
