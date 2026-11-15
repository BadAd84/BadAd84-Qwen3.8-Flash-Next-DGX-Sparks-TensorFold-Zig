#!/usr/bin/env bash
# dockvideo.sh - inside an ubuntu:24.04 container with a C compiler (CI's runner has `cc`; dockhost.sh's container did
# not): test-video-layout-linux on main alone and on main plus the widths patch. Results appended to /out/video.log.
set -u
O=/out/video.log
: > "$O"
say() { echo "$*" | tee -a "$O"; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /out/apt4.log 2>&1 && apt-get install -y -qq git python3 xz-utils curl ca-certificates gcc libc6-dev >> /out/apt4.log 2>&1 ||
  { say "SETUP apt failed"; exit 1; }
curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz || { say "SETUP zig failed"; exit 1; }
mkdir -p /opt && tar -xJf /tmp/zig.tar.xz -C /opt && Z=/opt/zig-x86_64-linux-0.17.0/zig
say "SETUP zig $($Z version) cc $(cc --version | head -1) base.tar $(sha256sum /in/base.tar | cut -c1-16) patch $(sha256sum /in/widths.patch | cut -c1-16)"
for tree in base head; do
  mkdir -p /b/$tree && tar -xf /in/base.tar -C /b/$tree && (cd /b/$tree && git init -q) || { say "SETUP $tree failed"; exit 1; }
done
(cd /b/head && git apply --whitespace=nowarn /in/widths.patch) || { say "SETUP patch failed"; exit 1; }
for tree in base head; do
  log=/out/video-$tree.log
  (cd /b/$tree && timeout 3600 "$Z" build -Dfixed-cpu test-video-layout-linux -j6 --maxrss 6000000000 --summary all > "$log" 2>&1)
  say "STEP $tree -Dfixed-cpu test-video-layout-linux rc $? $(tr '\r' '\n' < "$log" | grep -a 'Build Summary' | tail -1)"
done
say "DOCKVIDEO DONE $(date -u +%H:%M:%S)"
