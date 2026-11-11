#!/usr/bin/env bash
# rungs.sh - build the additive rungs after the stock stages finish (no compile runs beside a timed arm):
#   rung1 = 0001-0005 (rows)                        -> image stack126a (already built)
#   rung2 = rung1 + 0006-0012 + 0012b (kv8, with the draft head left as bf16 and the rows lever's draft hunks kept)
#   rung3 = rung2 + 0013-0015 (n-gram)
# 0012b replaces the blanket revert that the old integration tail (0030) did to cuda_mtp_draft.zig and
# cuda_mtp_ops.zig, which also deleted the rows, draft-head and read-out levers' own changes to those files.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 400); do [ -f BUILDUP2-DONE ] && break; sleep 30; done
echo "=== stock stages done, building rungs $(date -Is)"
mk() {
  local tag=$1 upto=$2 dir=patches126/$1
  rm -rf "$dir" && mkdir -p "$dir"
  for p in patches126/00*.patch; do
    n=$(basename "$p"); n=${n%%-*}
    [ "$n" \> "$upto" ] && break
    cp "$p" "$dir/"
  done
  [ "$upto" \> "0011" ] && cp rungfix/0012b-flashnext-kv8-leaves-the-draft-head-bf16.patch "$dir/0012b-flashnext-kv8-leaves-the-draft-head-bf16.patch"
  echo "--- $tag: $(ls "$dir"/*.patch | wc -l) patches"
  bash ./build_patches.sh "$tag" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$dir" > "build-$tag.log" 2>&1
  echo "build $tag rc=$? $(grep -aE '^BUILT' "build-$tag.log" | head -1)"
  grep -aoE "zig/[a-z_/0-9]+\.zig:[0-9]+:[0-9]+: error: .*" "build-$tag.log" | sort -u | head -8 | cut -c1-170
  bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$tag" embedded > /dev/null 2>&1
}
mk rung2 0012
mk rung3 0015
echo "=== rungs built $(date -Is)"
touch RUNGS-DONE
