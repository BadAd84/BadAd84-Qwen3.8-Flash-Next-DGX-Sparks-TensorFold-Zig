#!/usr/bin/env bash
# plebin.sh - run the head tree's compiled test binaries that hold the row-cache tests directly, once with no TF_
# variable and once with config.sh's exports, and list every PLE test each run reports.
cd ~/work/restack2/host/head || exit 1
unset_tf=$(env | grep -oE '^(TF_|TENSORFOLD_)[A-Za-z0-9_]+' | sed 's/^/-u /' | tr '\n' ' ')
for bin in $(grep -l --binary-files=binary "cuda_ple_cache_test.test" .zig-cache-clean/o/*/test 2>/dev/null); do
  echo "== $bin ($(stat -c %s "$bin") bytes)"
  for envname in clean prod; do
    if [ "$envname" = clean ]; then
      out=$(env $unset_tf "$bin" 2>&1)
    else
      out=$(source ~/qwen-zig/scripts/config.sh > /dev/null 2>&1; echo "TF_FLASHNEXT_GATHER_READ=$TF_FLASHNEXT_GATHER_READ" >&2; "$bin" 2>&1)
    fi
    echo "-- $envname: rc=$? $(echo "$out" | grep -E '^[0-9]+ passed|All [0-9]+ tests passed|passed;' | tail -1)"
    echo "$out" | grep -E 'cuda_ple_cache_test|cuda_ple_nvfp4_test|leaked|FAIL' | sed -E 's/^[0-9]+\/[0-9]+ //' | cut -c1-150
  done
done
