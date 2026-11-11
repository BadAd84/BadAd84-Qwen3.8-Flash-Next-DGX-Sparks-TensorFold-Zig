#!/usr/bin/env bash
# rungs2.sh - build the later additive rungs, each from ONE cumulative patch against pristine 6e9af930
# (work/rungs/rNNNN.patch, produced by mkrung.sh + overlay.py). Runs after rungs.sh so no compile sits beside a
# timed arm. A rung that fails to compile prints its distinct errors; nothing is measured here.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 600); do [ -f RUNGS-DONE ] && break; sleep 30; done
echo "=== first rungs done, building the later rungs $(date -Is)"
for K in 0017 0019 0021 0025 0026 0027 0029 0032; do
  dir=patches126/r$K
  rm -rf "$dir" && mkdir -p "$dir" && cp "rungs/r$K.patch" "$dir/0001-rung-$K.patch"
  bash ./build_patches.sh "r$K" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-r$K.log" 2>&1
  rc=$?
  echo "build r$K rc=$rc $(grep -aE '^BUILT' "build-r$K.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-r$K.log" | sort -u | head -10 | cut -c1-180
  [ "$rc" = 0 ] && bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:r$K" embedded > /dev/null 2>&1
done
echo "=== later rungs done $(date -Is)"
touch RUNGS2-DONE
