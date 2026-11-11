#!/usr/bin/env bash
# prodarm.sh - the production arm, properly: the zmerge8 image relabelled for the recipe's kernel gate, one fresh
# boot per level at the target's settings (nvfp4, fp8, 262,144), then the production serve restored.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 240); do [ -f CATCHUP-DONE ] && break; sleep 30; done
echo "=== catchup done, preparing the production arm $(date -Is)"
docker tag tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 tensorfold-qwen38:prodbench
bash ~/work/lanes/fp4port/relabel.sh tensorfold-qwen38:prodbench embedded
for C in 1 2 4 6; do
  IMG=tensorfold-qwen38:prodbench CHKPT=nvfp4 KV_DTYPE=fp8 CONTEXT=262144 \
    bash ./bench_arm.sh "prod2" "$C"
  echo "cell prod2 C=$C $(grep -aE '^BOOT seconds|^GOLD exit|not an image' "bench/prod2/c$C/arm.log" | tr '\n' ' ')"
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|rror" | head -2
echo "=== production $(date -Is)"
touch "$HOME/work/target/PRODARM-DONE"
