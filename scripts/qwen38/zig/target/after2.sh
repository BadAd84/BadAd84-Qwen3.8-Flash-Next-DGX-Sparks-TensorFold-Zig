#!/usr/bin/env bash
# after2.sh - once the stock 1.2.6 image exists, build our stack as stack126 from the PRISTINE upstream ref plus the
# numbered patch series (the TensorFold tree is never edited: the patches are the change).
set -u
cd "$HOME/work/target" || exit 1
until docker image inspect tensorfold-qwen38:up126 > /dev/null 2>&1; do sleep 30; done
echo "=== up126 present $(date -Is), building stack126 from $(ls patches126/*.patch | wc -l) patches"
bash "$HOME/work/target/build_patches.sh" stack126 git://192.168.99.16/up-pr/tf \
  6e9af930261a88bb28ac0bfb157ce8e57e9eea07 "$HOME/work/target/patches126" > build-stack126.log 2>&1
echo "build stack126 rc=$? $(docker image inspect tensorfold-qwen38:stack126 --format '{{.Id}}' 2>/dev/null | cut -c8-19)"
grep -aE "^BUILT|error:|error\[" build-stack126.log | tail -5
