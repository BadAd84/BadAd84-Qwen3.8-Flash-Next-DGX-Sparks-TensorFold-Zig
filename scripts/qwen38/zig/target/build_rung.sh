#!/usr/bin/env bash
# build_rung.sh TAG CUMULATIVE.patch - one image from one cumulative patch on pristine 6e9af930, relabelled so the
# recipe boots it. Skips an image that already exists. Prints one line (and the distinct compile errors, if any).
set -u
cd ~/work/target || exit 1
TAG=${1:?tag}; PATCH=${2:?cumulative patch}
if docker image inspect "tensorfold-qwen38:$TAG" > /dev/null 2>&1; then echo "build $TAG: image exists"; exit 0; fi
dir=patches126/$TAG
rm -rf "$dir" && mkdir -p "$dir" && cp "$PATCH" "$dir/0001-$TAG.patch"
bash ./build_patches.sh "$TAG" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$TAG.log" 2>&1
rc=$?
echo "build $TAG rc=$rc $(grep -aE '^BUILT' "build-$TAG.log" | head -1)"
grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-$TAG.log" | sort -u | head -8 | cut -c1-180
[ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$TAG" embedded > /dev/null 2>&1
exit "$rc"
