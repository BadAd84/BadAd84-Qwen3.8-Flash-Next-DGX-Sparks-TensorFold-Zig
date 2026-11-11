#!/usr/bin/env bash
# bisect2.sh - narrow the rows regression inside 0016-0030 by booting two prefixes: 0001-0021 and 0001-0025.
# Each build comes from the patch pipeline, so a failure here is a real compile dependency, not a stale tree.
set -u
cd ~/work/target || exit 1
for i in $(seq 1 200); do [ -f ENVPROD-DONE ] && break; sleep 30; done
echo "=== env arm done, bisecting $(date -Is)"
for upto in 0021 0025; do
  rm -rf "patches126/p$upto" && mkdir -p "patches126/p$upto"
  for p in patches126/*.patch; do
    n=$(basename "$p"); n=${n%%-*}
    [ "$n" \> "$upto" ] && break
    cp "$p" "patches126/p$upto/"
  done
  echo "--- prefix-$upto: $(ls "patches126/p$upto"/*.patch | wc -l) patches"
  bash ./build_patches.sh "stack126p$upto" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 \
    "patches126/p$upto" > "build-p$upto.log" 2>&1
  rc=$?
  echo "build p$upto rc=$rc $(grep -ac 'error:' "build-p$upto.log") errors"
  grep -aE 'error:' "build-p$upto.log" | head -3
  [ "$rc" = 0 ] || continue
  bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:stack126p$upto" embedded > /dev/null 2>&1
  cd ~/work/lanes/rpr/recipe || exit 1
  ( PREPARE=0 IMAGE="tensorfold-qwen38:stack126p$upto" CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native \
    KV_DTYPE=fp8 PARALLEL=1 CONTEXT=131072 HOST=127.0.0.1 ./start.sh restart </dev/null ) > "/tmp/p$upto-boot.log" 2>&1
  echo "prefix-$upto self-check: $(docker logs qwen38-flash-next-tf 2>&1 | grep -a 'self-check\|copy windows' | head -2 | tr '\n' ' ' | cut -c1-160)"
  ( ./stop.sh ) > /dev/null 2>&1
  cd ~/work/target || exit 1
done
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a "answered\|rror" | head -2
echo "=== production $(date -Is)"
touch "$HOME/work/target/BISECT2-DONE"
