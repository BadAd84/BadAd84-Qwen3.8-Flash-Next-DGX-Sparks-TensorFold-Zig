#!/usr/bin/env bash
# build.sh - build tensorfold-qwen38:main-9a38b1f7b from a git archive of upstream main's tip.
# Runs on spark6 (docker build is CPU only, no GPU lock). Log: ~/work/SharedDraftsMain/build/build.log.
set -euo pipefail
SHA=9a38b1f7b33863507cdea47e88207d8b3bea3f22
TAG=tensorfold-qwen38:main-9a38b1f7b
BOX=$HOME/work/SharedDraftsMain/build
cd "$BOX"
rm -rf src
mkdir src
tar -xzf ../main-9a38b1f7b.tar.gz -C src --strip-components=1
echo "$SHA" > SOURCE_SHA
cp ../Dockerfile Dockerfile
{
  echo "BUILD_START $(date -Is)"
  echo "SOURCE_SHA $SHA"
  echo "SOURCE_TARBALL_SHA256 $(sha256sum ../main-9a38b1f7b.tar.gz | cut -d' ' -f1)"
  echo "IMAGE_TAG $TAG"
  set +e
  docker build --progress=plain -t "$TAG" .
  rc=$?
  echo "BUILD_RC=$rc"
  docker image inspect "$TAG" --format 'IMAGE_ID {{.Id}} CREATED {{.Created}} SIZE {{.Size}}'
  docker run --rm "$TAG" --version
  echo "BUILD_DONE $(date -Is)"
} > build.log 2>&1
tail -6 build.log
