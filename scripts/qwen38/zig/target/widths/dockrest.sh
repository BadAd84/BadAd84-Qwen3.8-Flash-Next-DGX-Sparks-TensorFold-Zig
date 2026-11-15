#!/usr/bin/env bash
# dockrest.sh - inside an ubuntu:24.04 container, set up as dockersteps.sh: test-release-directory-host on main alone
# and on the head (the step that failed inside test-host), then the mutants dockersteps.sh did not reach. Inputs at
# /in, results appended to /out/rest.log.
set -u
O=/out/rest.log
: > "$O"
say() { echo "$*" | tee -a "$O"; }
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq > /out/apt2.log 2>&1 && apt-get install -y -qq git python3 xz-utils curl ca-certificates >> /out/apt2.log 2>&1 ||
  { say "SETUP apt failed"; exit 1; }
curl -fsSL -o /tmp/zig.tar.xz https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz || { say "SETUP zig failed"; exit 1; }
mkdir -p /opt && tar -xJf /tmp/zig.tar.xz -C /opt && Z=/opt/zig-x86_64-linux-0.17.0/zig
say "SETUP zig $($Z version) base.tar $(sha256sum /in/base.tar | cut -c1-16) patch $(sha256sum /in/widths.patch | cut -c1-16)"
for tree in base head; do
  mkdir -p /b/$tree && tar -xf /in/base.tar -C /b/$tree && (cd /b/$tree && git init -q) || { say "SETUP $tree failed"; exit 1; }
done
(cd /b/head && git apply --whitespace=nowarn /in/widths.patch) || { say "SETUP patch failed"; exit 1; }
for tree in base head; do
  log=/out/rest-$tree-release.log
  (cd /b/$tree && timeout 3600 "$Z" build -Dfixed-cpu test-release-directory-host -j6 --maxrss 6000000000 --summary all > "$log" 2>&1)
  say "STEP $tree -Dfixed-cpu test-release-directory-host rc $? $(tr '\r' '\n' < "$log" | grep -a -E 'Build Summary|release privacy' | head -2 | tr '\n' ' ')"
done
for m in mtp-any captured-any fixed-top10; do
  rm -rf /b/mut && cp -r /b/head /b/mut && python3 /in/mutants.py "$m" /b/mut > /dev/null || { say "MUTANT $m APPLY FAILED"; continue; }
  (cd /b/mut && timeout 3600 "$Z" build test-cuda-host -j6 --maxrss 6000000000 > "/out/mut-$m.log" 2>&1)
  rc=$?
  say "MUTANT $m rc $rc $(tr '\r' '\n' < "/out/mut-$m.log" | grep -a -E "error: '.*' (failed|terminated)|: error: " | sort -u | head -3 | tr '\n' ' ' | cut -c1-400)"
done
rm -rf /b/mut
say "DOCKREST DONE $(date -u +%H:%M:%S)"
