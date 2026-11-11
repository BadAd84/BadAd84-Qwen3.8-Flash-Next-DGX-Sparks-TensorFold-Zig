#!/usr/bin/env bash
# catchup.sh - the head-to-head at the target's own settings: nvfp4, fp8 KV, 262,144 tokens, per-stream busy.
# Arms: the production zmerge8 image and our 1.2.6 stack, cells at 1, 2, 4 and 6 streams, then production restored.
set -u
cd "$HOME/work/target" || exit 1
for entry in "prod:zmerge8-kfix-e5139fcd8c6101c7" "stack:stack126"; do
  name=${entry%%:*}; img=${entry##*:}
  for C in 1 2 4 6; do
    IMG="tensorfold-qwen38:$img" CHKPT=nvfp4 KV_DTYPE=fp8 CONTEXT=262144 \
      bash ./bench_arm.sh "catchup-$name" "$C"
    echo "cell catchup-$name C=$C $(grep -aE '^BOOT seconds|^GOLD exit|^BOOT FAILED' "bench/catchup-$name/c$C/arm.log" | tr '\n' ' ')"
  done
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|rror" | head -2
echo "=== production $(date -Is)"
touch "$HOME/work/target/CATCHUP-DONE"
