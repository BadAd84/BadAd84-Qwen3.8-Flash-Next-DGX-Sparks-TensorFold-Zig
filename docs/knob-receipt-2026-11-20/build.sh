#!/usr/bin/env bash
# build.sh - the one serve image for the knob receipt on spark6: upstream main 1ece6e6db (M), built from a
# git-archive tree verified blob by blob against `git ls-tree -r`.
#
# Same procedure as the copy-window receipt's build.sh: build stage nvcr.io/nvidia/pytorch:26.07-py3 with Zig
# 0.17.0 downloaded and SHA-256 checked, `zig build -Dnvcc=... -Doptimize=fast fatbins install native`, then
# native/, bin/ and fatbin/ copied into the runtime image tensorfold-qwen38:zig-db28187, and the tf.kernels label
# set to embedded for the recipe's gate. A build that comes out of the builder cache with no SOURCE line of its
# own is deleted and rebuilt with --no-cache, so the image carries this run's own compile.
#
# The GPU lock is held by the caller (flock in chain_build.sh / the driver); production keeps serving while this
# builds, so each build waits for 14 GiB MemAvailable and is capped at 12 CPUs and 24 GiB (32 with swap).
set -euo pipefail
cd "$HOME/work/KnobTest"
MAIN_SHA=1ece6e6dbbc073582d50738ce8e73e3c3261a73b
MI=knob-m-${MAIN_SHA:0:8}
BASE_IMAGE=nvcr.io/nvidia/pytorch:26.07-py3
BASEIMG=tensorfold-qwen38:zig-db28187
ZIG_VERSION=0.17.0
ZIG_SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8

( source "$HOME/qwen-zig/scripts/config.sh"
  [ "${BASE_IMAGE:-}" = "$BASE_IMAGE" ] || { echo "BASE_IMAGE drift: ${BASE_IMAGE:-unset}"; exit 1; }
  [ "${ZIG_VERSION:-}" = "$ZIG_VERSION" ] || { echo "ZIG_VERSION drift: ${ZIG_VERSION:-unset}"; exit 1; }
  [ "${ZIG_SHA256:-}" = "$ZIG_SHA256" ] || { echo "ZIG_SHA256 drift: ${ZIG_SHA256:-unset}"; exit 1; }
  echo "config check: BASE_IMAGE $BASE_IMAGE ZIG $ZIG_VERSION sha ${ZIG_SHA256:0:16}" )
docker image inspect "$BASEIMG" > /dev/null || { echo "runtime image $BASEIMG missing"; exit 1; }
docker image inspect "$BASE_IMAGE" > /dev/null || { echo "build image $BASE_IMAGE missing"; exit 1; }
mkdir -p out in
[ -f in/main.tar.gz ] && [ -f in/main.manifest ] || { echo "in/main.tar.gz or in/main.manifest missing"; exit 1; }

memavail() { awk '/MemAvailable/{print int($2/1048576)}' /proc/meminfo; }
wait_mem() {
  local i
  for i in $(seq 1 90); do
    [ "$(memavail)" -ge 14 ] && return 0
    sleep 10
  done
  echo "MemAvailable stayed under 14 GiB: not building"
  return 1
}

rm -rf MAIN && mkdir -p MAIN/src
tar -xzf in/main.tar.gz -C MAIN/src
python3 scripts/verify_tree.py in/main.manifest MAIN/src || { echo "TREE MAIN FAILED its manifest"; exit 1; }
echo "TREE MAIN extracted from $MAIN_SHA"
cat > MAIN/Dockerfile <<'DOCKER'
ARG BASE_IMAGE
ARG BASEIMG
FROM ${BASE_IMAGE} AS build
ARG ZIG_VERSION
ARG ZIG_SHA256
ARG SRC_SHA
RUN curl -fsSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" && \
    echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - && \
    mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz
COPY src/ /tensorfold/
RUN echo "SOURCE ${SRC_SHA}" && \
    echo "NVCC $(/usr/local/cuda/bin/nvcc --version | tail -2 | tr '\n' ' ')" && \
    echo "ZIG $(/opt/zig/zig version)" && \
    cd /tensorfold && /opt/zig/zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold \
      -j"$(nproc)" fatbins install native && test -x /opt/tensorfold/native/bin/tensorfold-native && echo "BUILD OK"
FROM ${BASEIMG}
COPY --from=build /opt/tensorfold/native /opt/tensorfold/native
COPY --from=build /opt/tensorfold/bin /opt/tensorfold/bin
COPY --from=build /opt/tensorfold/fatbin /opt/tensorfold/fatbin
DOCKER

build_one() { # image sha
  local img=$1 sha=$2 rc=0
  if docker image inspect "tensorfold-qwen38:$img" > /dev/null 2>&1; then
    echo "image tensorfold-qwen38:$img exists: refusing to reuse it"; return 1
  fi
  wait_mem
  echo "=== build $img from $sha $(date -Is) mem_avail $(memavail) GiB"
  docker build --progress=plain --memory 24g --memory-swap 32g --cpu-quota 1200000 \
    -t "tensorfold-qwen38:$img" \
    --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg BASEIMG="$BASEIMG" \
    --build-arg ZIG_VERSION="$ZIG_VERSION" --build-arg ZIG_SHA256="$ZIG_SHA256" --build-arg SRC_SHA="$sha" \
    -f MAIN/Dockerfile MAIN > "out/build-$img.log" 2>&1 || rc=$?
  echo "build $img rc $rc $(date -Is) mem_avail $(memavail) GiB"
  if [ "$rc" != 0 ]; then tail -40 "out/build-$img.log"; return 1; fi
  if ! grep -q "SOURCE $sha" "out/build-$img.log"; then
    echo "CACHE-HIT $img carried no SOURCE line of its own: deleting and rebuilding with --no-cache"
    docker rmi "tensorfold-qwen38:$img" > /dev/null
    rc=0
    docker build --progress=plain --no-cache --memory 24g --memory-swap 32g --cpu-quota 1200000 \
      -t "tensorfold-qwen38:$img" \
      --build-arg BASE_IMAGE="$BASE_IMAGE" --build-arg BASEIMG="$BASEIMG" \
      --build-arg ZIG_VERSION="$ZIG_VERSION" --build-arg ZIG_SHA256="$ZIG_SHA256" --build-arg SRC_SHA="$sha" \
      -f MAIN/Dockerfile MAIN > "out/build-$img.log" 2>&1 || rc=$?
    echo "rebuild $img rc $rc $(date -Is) mem_avail $(memavail) GiB"
    if [ "$rc" != 0 ]; then tail -40 "out/build-$img.log"; return 1; fi
    grep -q "SOURCE $sha" "out/build-$img.log" || { echo "STILL no SOURCE line for $img"; return 1; }
  fi
  bash "$HOME/work/lanes/fp4port/relabel.sh" "tensorfold-qwen38:$img" embedded
}

build_one "$MI" "$MAIN_SHA"
{
  docker image inspect -f 'IMAGE {{.RepoTags}} id={{.Id}} created={{.Created}} kernels={{index .Config.Labels "tf.kernels"}} size={{.Size}}' "tensorfold-qwen38:$MI"
  grep -a -h -E "SOURCE |NVCC |ZIG |BUILD OK" out/build-"$MI".log | sed 's/^/  /'
} | tee out/build.out
echo "BUILD-DONE $(date -Is)"
