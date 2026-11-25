# Task #4803: a clean build of upstream TensorFold main, none of the OTS patch stack, none of our levers.
# Source is a git archive of main's tip (src/ in the build context); SOURCE_SHA is that commit, copied in.
# Toolchain: Zig 0.17.0 (.zig-version) at the sha256 the recipe pins; nvcc from nvcr.io/nvidia/pytorch:26.07-py3.
# Build step is the one main's own receipts use (docs/receipts/flashnext-prompt-chunk3072/README.md:9):
#   zig build -Dnvcc=... -Doptimize=fast fatbins install native
FROM nvcr.io/nvidia/pytorch:26.07-py3 AS build
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends xz-utils ca-certificates \
    && rm -rf /var/lib/apt/lists/*
ARG ZIG_VERSION=0.17.0
ARG ZIG_SHA256=9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
RUN curl -fsSL -o /tmp/zig.tar.xz "https://ziglang.org/download/${ZIG_VERSION}/zig-aarch64-linux-${ZIG_VERSION}.tar.xz" \
    && echo "${ZIG_SHA256}  /tmp/zig.tar.xz" | sha256sum -c - \
    && mkdir -p /opt/zig && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 && rm /tmp/zig.tar.xz
COPY SOURCE_SHA /SOURCE_SHA
COPY src/ /tensorfold/
RUN echo "SOURCE_SHA $(cat /SOURCE_SHA)" \
    && echo "TREE $(sha256sum /tensorfold/CHANGELOG.md | cut -d' ' -f1) changelog-sha" \
    && echo "ZIG $(/opt/zig/zig version)" \
    && echo "ZIG_ARCHIVE_SHA256 ${ZIG_SHA256}" \
    && echo "NVCC $(/usr/local/cuda/bin/nvcc --version | tail -2 | tr '\n' ' ')"
RUN cd /tensorfold && /opt/zig/zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold \
      -j"$(nproc)" fatbins install native && test -x /opt/tensorfold/native/bin/tensorfold-native \
    && echo "BUILD OK $(sha256sum /opt/tensorfold/native/bin/tensorfold-native)"

FROM nvcr.io/nvidia/pytorch:26.07-py3
COPY --from=build /opt/tensorfold /opt/tensorfold
ENV PATH=/opt/tensorfold/native/bin:/opt/tensorfold/bin:/usr/local/cuda/bin:$PATH \
    HF_HOME=/huggingface \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility
ENTRYPOINT ["/opt/tensorfold/native/bin/tensorfold-native"]
CMD ["--version"]
