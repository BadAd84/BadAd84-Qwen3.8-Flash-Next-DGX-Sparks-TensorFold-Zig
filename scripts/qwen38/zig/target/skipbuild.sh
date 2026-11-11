#!/usr/bin/env bash
# skipbuild.sh - the code-only patches, evaluated as full-series-minus-one: build the 31-patch series with one patch
# dropped (only the ones that still apply), then one arm at C=1 and C=4 with the measured serve environment.
# Already built: 0026 (stack126noq12). Then production restored.
set -u
cd ~/work/target || exit 1
for skip in 0019 0024 0025 0027; do
  rm -rf "patches126/skip$skip" && mkdir -p "patches126/skip$skip"
  for p in patches126/*.patch; do
    case "$(basename "$p")" in "$skip"-*) continue ;; esac
    cp "$p" "patches126/skip$skip/"
  done
  echo "=== skip-$skip: $(ls "patches126/skip$skip"/*.patch | wc -l) patches $(date -Is)"
  bash ./build_patches.sh "sk$skip" git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 \
    "patches126/skip$skip" > "build-sk$skip.log" 2>&1
  rc=$?
  echo "build sk$skip rc=$rc $(grep -aE '^BUILT|error:' "build-sk$skip.log" | head -2)"
  [ "$rc" = 0 ] || continue
  bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:sk$skip" embedded > /dev/null 2>&1
  E=$(bash ./serve-env126.sh)
  IMG="tensorfold-qwen38:sk$skip" bash ./patcheval.sh "sk$skip:$E" > "arm-sk$skip.log" 2>&1
done
E=$(bash ./serve-env126.sh)
IMG=tensorfold-qwen38:stack126noq12 bash ./patcheval.sh "sk0026:$E" > arm-sk0026.log 2>&1
( cd "$HOME/work/lanes/rpr/recipe" && ./stop.sh ) > /dev/null 2>&1
( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null ) 2>&1 | grep -a answered | head -1
echo "=== production $(date -Is)"
touch "$HOME/work/target/SKIPBUILD-DONE"
