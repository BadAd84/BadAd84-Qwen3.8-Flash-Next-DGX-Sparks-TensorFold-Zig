#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
SRC=$(readlink -f src.tar)
ctx=$(mktemp -d "$PWD/ctxk.XXXXXX"); trap "rm -rf -- $ctx" EXIT
cp "$SRC" "$ctx/src.tar"
cp Dockerfile.zmerge8k "$ctx/Dockerfile"
exec > >(tee "build-zmerge8k.log") 2>&1
echo "=== build zmerge8-kfix from $(sha256sum "$SRC" | cut -c1-16) onto tensorfold-qwen38:zmerge8 $(date -Is)"
mkdir -p ~/work
flock -o ~/work/gpu.lock docker build -t "tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7" \
  --label "ai-engine.kindling=0001-vision-clone+0002-upload-staging (byte-neutral 64k boot fixes)" \
  --label "ai-engine.src-sha256=$(sha256sum < "$SRC" | cut -c1-16)" \
  --build-arg BASE_IMAGE=nvcr.io/nvidia/pytorch:26.07-py3 \
  --build-arg SRCIMG=tensorfold-qwen38:zmerge8 \
  --build-arg ZIG_VERSION=0.17.0 --build-arg ZIG_SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8 \
  -f "$ctx/Dockerfile" "$ctx"
echo "BUILT tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 $(date -Is)"
