#!/usr/bin/env bash
# dockhost.sh - inside an ubuntu:24.04 container, set up as dockersteps.sh: the no-GPU workflow's test-host step
# (-Dfixed-cpu, 20-minute test limit) on main alone, then on main plus the widths patch, one at a time, with each
# run's failed steps and failed, crashed or timed-out tests. Inputs at /in, results appended to /out/host.log.
set -u
O=/out/host.log
: > "$O"
say() { echo "$*" | tee -a "$O"; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /out/apt3.log 2>&1 && apt-get install -y -qq git python3 xz-utils curl ca-certificates >> /out/apt3.log 2>&1 ||
  { say "SETUP apt failed"; exit 1; }
curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz || { say "SETUP zig failed"; exit 1; }
mkdir -p /opt && tar -xJf /tmp/zig.tar.xz -C /opt && Z=/opt/zig-x86_64-linux-0.17.0/zig
say "SETUP zig $($Z version) base.tar $(sha256sum /in/base.tar | cut -c1-16) patch $(sha256sum /in/widths.patch | cut -c1-16)"
for tree in base head; do
  mkdir -p /b/$tree && tar -xf /in/base.tar -C /b/$tree && (cd /b/$tree && git init -q) || { say "SETUP $tree failed"; exit 1; }
done
(cd /b/head && git apply --whitespace=nowarn /in/widths.patch) || { say "SETUP patch failed"; exit 1; }
for tree in base head; do
  log=/out/host-$tree.log
  (cd /b/$tree && timeout 7200 "$Z" build -Dfixed-cpu test-host --test-timeout 20m -j6 --maxrss 6000000000 --summary failures > "$log" 2>&1)
  say "STEP $tree -Dfixed-cpu test-host rc $? $(tr '\r' '\n' < "$log" | grep -a 'Build Summary' | tail -1)"
  tr '\r' '\n' < "$log" | grep -a -E "error: '.*' (failed|terminated|timed out)|^ *\+- run (exe|test) .* (failure|failed)|failed command" |
    sed 's/^/  /' | sort -u | head -12 | cut -c1-200 | tee -a "$O"
done
say "DOCKHOST DONE $(date -u +%H:%M:%S)"
