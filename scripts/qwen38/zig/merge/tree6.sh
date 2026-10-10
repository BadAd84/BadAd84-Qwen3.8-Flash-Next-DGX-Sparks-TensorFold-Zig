#!/usr/bin/env bash
# tree6.sh: r2e-fable's tree replay re-priced on the same sweep's zmerge5 and zmerge6 boot cost tables (CPU only).
cd ~/work/lanes/r2e-fable || exit 1
for arm in base ours; do
  log=~/work/zab-zrm-m6a-$arm.log
  for mode in "" "--raw"; do
    for ov in "--head-row 0 --tree-over 0" "--head-row 0.4 --tree-over 1.0"; do
      echo "######## $arm ${mode:-fit} $ov"
      # shellcheck disable=SC2086
      python3 r2e_replay.py r2e-trace.txt "$log" $mode $ov --brief 2>&1 | grep -a "costs:\|chain\|rank-2\|gated\|>= 0.05\|>= 0.10\|shape.best\|prose1\|code1\|cell" | head -30
    done
  done
done
