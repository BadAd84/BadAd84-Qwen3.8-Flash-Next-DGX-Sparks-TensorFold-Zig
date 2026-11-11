#!/usr/bin/env bash
# ladder.sh - the two buildable intermediate rungs on spark6: rows+kv8 (0001-0012) and rows to n-gram (0001-0015).
# Build each image from the patch subset, then one arm at C=1 and C=4 with the standard cell, then restore the
# production serve.
set -u
cd "$HOME/work/target" || exit 1
build() {
  local tag=$1 dir=$2
  echo "--- build $tag from $(ls "$dir"/*.patch | wc -l) patches $(date -Is)"
  bash "$HOME/work/target/build_patches.sh" "$tag" git://192.168.99.16/up-pr/tf \
    6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$tag.log" 2>&1
  echo "build $tag rc=$? $(grep -aE '^BUILT|error:' "build-$tag.log" | head -2)"
  bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$tag" embedded > /dev/null 2>&1
}
arm() {
  local name=$1 img=$2
  for C in 1 4; do
    echo "--- cell $name C=$C $(date -Is)"
    IMG="tensorfold-qwen38:$img" KV_DTYPE=bf16 CONTEXT=131072 bash ./bench_arm.sh "$name" "$C"
    echo "cell $name C=$C rc=$? $(grep -aE '^BOOT seconds|^GOLD exit|^PROBE|BOOT FAILED' "bench/$name/c$C/arm.log" | tr '\n' ' ')"
  done
}
rm -rf sub-kv sub-ng; mkdir -p sub-kv sub-ng
cp patches126/00[01][0-9]-*.patch sub-kv/ 2>/dev/null; rm -f sub-kv/001[3-9]-*.patch sub-kv/002*-*.patch sub-kv/003*-*.patch
cp patches126/000[1-9]-*.patch patches126/001[0-5]-*.patch sub-ng/ 2>/dev/null
build stack126kv sub-kv
build stack126ng sub-ng
arm kv stack126kv
arm ng stack126ng
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|LIVE\|rror" | head -3
echo "=== production restored $(date -Is)"
touch "$HOME/work/target/LADDER-DONE"
