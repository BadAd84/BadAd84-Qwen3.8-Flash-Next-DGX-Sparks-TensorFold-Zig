#!/usr/bin/env bash
# chain.sh TAG CELL... - build tensorfold-qwen38:TAG from ~/work/int4/patches, label it, then one GPU window of CELLs
# (int4win.sh). Log: ~/work/int4/chain-TAG.log.
set -u
TAG=$1; shift
cd ~/work/target || exit 1
bash ~/work/target/build_patches.sh "$TAG" git://192.168.99.16/up-pr/tf 93a2e93ecebff8aa52b88e58c5dd222516e69c5f \
  ~/work/int4/patches > ~/work/int4/build-"$TAG".log 2>&1 || { echo "BUILD FAILED"; grep -a -m5 "error" ~/work/int4/build-"$TAG".log; exit 1; }
echo "built $(date -Is)"
bash ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:$TAG" embedded > /dev/null 2>&1
IMG="tensorfold-qwen38:$TAG" OUT="$HOME/work/int4/bench-$TAG" bash ~/work/int4/int4win.sh "$@"
echo "chain done $(date -Is)"
