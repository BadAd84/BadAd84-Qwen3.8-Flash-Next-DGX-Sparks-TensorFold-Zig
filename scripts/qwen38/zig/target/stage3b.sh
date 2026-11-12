#!/usr/bin/env bash
# stage3b.sh - the rest of stage 3 on the accepted rung (through old 0021), skipping the broken read-out fusion
# group (0022-0025): q12 (0026), cost (0027), vision (0028-0029), the reader knob and check log (0031-0032), each
# against the rung before it. r0025x (the read-out group without its faulting head-pieces path) is measured too,
# only to price that lever: it serves but its self-check reads 0 of 2,080.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 600); do [ -f ACCEPTED-DONE ] && break; sleep 30; done
echo "=== building the continuation rungs $(date -Is)"
for T in m26 m27 m29 m32 n32; do
  dir=patches126/$T
  rm -rf "$dir" && mkdir -p "$dir" && cp "rungs/$T.patch" "$dir/0001-rung-$T.patch"
  bash ./build_patches.sh "$T" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$T.log" 2>&1
  rc=$?
  echo "build $T rc=$rc $(grep -aE '^BUILT' "build-$T.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-$T.log" | sort -u | head -8 | cut -c1-180
  [ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$T" embedded > /dev/null 2>&1
done
export KV_DTYPE=bf16 CONTEXT=131072 NORESTORE=1
: > stage3b.log
run() {
  local name=$1 img=$2
  docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1 || { echo "=== $name: image $img missing" >> stage3b.log; return; }
  IMG="tensorfold-qwen38:$img" bash ./patcheval.sh "$name:" >> stage3b.log 2>&1
}
run b3warm r0021
run b3r21 r0021
run b3hcx r0025x
run b3q12 m26
run b3cost m27
run b3vision m29
run b3all m32
run b3noq12 n32
run b3r21b r0021
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch STAGE3B-DONE
