#!/usr/bin/env bash
# build_patches.sh TAG TF_REPO TF_REF PATCHDIR   (spark6, ~/work/target): tensorfold-qwen38:TAG = the recipe's Zig
# image with tensorfold-native and the fatbins rebuilt from a PRISTINE TensorFold at TF_REF plus the numbered patch
# series in PATCHDIR applied in filename order. No branch of ours is involved: the tree is upstream's, the changes
# are the patches. Log: build-TAG.log.
set -euo pipefail
TAG=$1; TF_REPO=$2; TF_REF=$3; PATCHDIR=$4
cd "$HOME/work/target" || exit 1
source ~/qwen-zig/scripts/config.sh
BASEIMG=${BASEIMG:-tensorfold-qwen38:zig-db28187}
echo "patches: $(ls "$PATCHDIR"/*.patch | wc -l) from $PATCHDIR"
docker build -t "tensorfold-qwen38:$TAG" --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg BASEIMG="$BASEIMG" \
  --build-arg TF_REPO="$TF_REPO" --build-arg TF_REF="$TF_REF" --build-arg ZIG_VERSION="$ZIG_VERSION" \
  --build-arg ZIG_SHA256="$ZIG_SHA256" -f - "$PATCHDIR" <<'DOCKERFILE'
ARG BASE_IMAGE
ARG BASEIMG
FROM ${BASE_IMAGE} AS build
ARG ZIG_VERSION
ARG ZIG_SHA256
RUN curl -fsSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" && \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - && \
    mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz
ARG TF_REPO
ARG TF_REF
RUN git init -q /tensorfold && cd /tensorfold && git remote add origin "${TF_REPO}" && \
    git fetch -q --depth 1 origin "${TF_REF}" && git checkout -q --detach FETCH_HEAD
COPY . /opt/ots-patches
RUN cd /tensorfold && for p in /opt/ots-patches/*.patch; do echo "applying $p"; \
      git apply --whitespace=nowarn "$p" || exit 1; done
RUN cd /tensorfold && /opt/zig/zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold \
      -j"$(nproc)" fatbins install native && test -x /opt/tensorfold/native/bin/tensorfold-native
FROM ${BASEIMG}
COPY --from=build /opt/tensorfold/native /opt/tensorfold/native
COPY --from=build /opt/tensorfold/bin /opt/tensorfold/bin
COPY --from=build /opt/tensorfold/fatbin /opt/tensorfold/fatbin
DOCKERFILE
echo "BUILT tensorfold-qwen38:$TAG"
