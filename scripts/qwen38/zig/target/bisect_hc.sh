#!/usr/bin/env bash
# bisect_hc.sh - bisect the read-out fusion group (0022-0025) on top of the accepted rung 0021: build each
# intermediate rung from its cumulative patch, then boot it once and report the smoke request and the self-check.
# r0025x is rung 0025 with cuda_mtp_ops.zig left as at rung 0021 (no head-pieces path).
set -u
cd ~/work/target || exit 1
for K in 0022 0023 0024 0025x; do
  dir=patches126/r$K
  rm -rf "$dir" && mkdir -p "$dir" && cp "rungs/r$K.patch" "$dir/0001-rung-$K.patch"
  bash ./build_patches.sh "r$K" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-r$K.log" 2>&1
  rc=$?
  echo "build r$K rc=$rc $(grep -aE '^BUILT' "build-r$K.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-r$K.log" | sort -u | head -8 | cut -c1-180
  [ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:r$K" embedded > /dev/null 2>&1
done
for K in 0021 0022 0023 0024 0025x 0025; do
  docker image inspect "tensorfold-qwen38:r$K" > /dev/null 2>&1 || { echo "r$K: no image"; continue; }
  NOPROD=1 bash ./probe_rung.sh "r$K" "r$K:" 2>&1 | grep -v "Server answered"
done
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
touch BISECTHC-DONE
