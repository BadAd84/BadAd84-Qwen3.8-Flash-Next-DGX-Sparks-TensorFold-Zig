#!/usr/bin/env bash
# dockersteps.sh - inside an ubuntu:24.04 container: zig 0.17.0 (x86_64 Linux release), then main alone (base.tar) and
# main plus the widths patch, each built in the container's own filesystem; runs the no-GPU workflow's host steps one
# zig build at a time (-j6 --maxrss 6000000000), the two steps whose tests reached the 20-minute limit on the head also
# on main, then each mutant on a copy of the head. Inputs mounted at /in, results appended to /out/steps.log.
set -u
O=/out/steps.log
: > "$O"
say() { echo "$*" | tee -a "$O"; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /out/apt.log 2>&1 && apt-get install -y -qq git python3 xz-utils curl ca-certificates >> /out/apt.log 2>&1 ||
  { say "SETUP apt failed"; exit 1; }
curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz ||
  { say "SETUP zig download failed"; exit 1; }
mkdir -p /opt && tar -xJf /tmp/zig.tar.xz -C /opt && Z=/opt/zig-x86_64-linux-0.17.0/zig
say "SETUP zig $($Z version) base.tar $(sha256sum /in/base.tar | cut -c1-16) patch $(sha256sum /in/widths.patch | cut -c1-16)"
git config --global user.email ci@example.invalid && git config --global user.name ci
for tree in base head; do
  mkdir -p /b/$tree && tar -xf /in/base.tar -C /b/$tree && (cd /b/$tree && git init -q) || { say "SETUP $tree failed"; exit 1; }
done
(cd /b/head && git apply --whitespace=nowarn /in/widths.patch) || { say "SETUP patch failed"; exit 1; }
step() { # tree words...
  local tree=$1; shift
  local log="/out/log-$tree-$(echo "$*" | tr ' /' '__').log"
  (cd /b/$tree && timeout 5400 "$Z" build "$@" -j6 --maxrss 6000000000 --summary all > "$log" 2>&1)
  local rc=$?
  say "STEP $tree $* rc $rc $(tr '\r' '\n' < "$log" | grep -a 'Build Summary' | tail -1)"
  tr '\r' '\n' < "$log" | grep -a -E "error: '.*' (failed|terminated|timed out)" | sed 's/^/  /' | head -8 | cut -c1-220 | tee -a "$O"
}
step base -Dfixed-cpu test-rows-startup-scale --test-timeout 20m
step base -Dfixed-cpu test-dsv41-device-host --test-timeout 20m
step head -Dfixed-cpu test-host --test-timeout 20m
step head -Dfixed-cpu test-golden
step head -Dfixed-cpu test-kernel-contract
step head -Dfixed-cpu fuzz-cortheon
step head -Dfixed-cpu test --test-timeout 10m
step head test-cuda-host
step head test-environment-host
for m in default-only mlx-any scratch-const mtp-any captured-any fixed-top10; do
  rm -rf /b/mut && cp -r /b/head /b/mut && python3 /in/mutants.py "$m" /b/mut > /dev/null || { say "MUTANT $m APPLY FAILED"; continue; }
  (cd /b/mut && timeout 3600 "$Z" build test-cuda-host -j6 --maxrss 6000000000 > "/out/mut-$m.log" 2>&1)
  rc=$?
  say "MUTANT $m rc $rc $(tr '\r' '\n' < "/out/mut-$m.log" | grep -a -E "error: '.*' (failed|terminated)|: error: " | sort -u | head -3 | tr '\n' ' ' | cut -c1-400)"
done
rm -rf /b/mut
say "DOCKERSTEPS DONE $(date -u +%H:%M:%S)"
