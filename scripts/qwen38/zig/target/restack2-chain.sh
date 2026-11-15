#!/usr/bin/env bash
# restack2-chain.sh - spark6, unattended: after the host suites (~/work/restack2/host/DONE) and any other docker build,
# build the two arms from pristine 964174ea05 (r2a: the re-seated package, all 19 patches; r2b: the package without
# 0004 and 0012), set tf.kernels=embedded on both (the rpr recipe's gate), then queue the GPU window A B B A at
# 1, 2, 4, 6 and 8 streams (restack2-win.sh). Log: ~/work/restack2/chain.log.
set -u
R=$HOME/work/restack2
BASE=964174ea05879e6dde1de1198a3aae3ef8b46a3b
log() { echo "=== $* $(date -Is)" | tee -a "$R/chain.log"; }
for _ in $(seq 1 720); do [ -f "$R/host/DONE" ] && break; sleep 20; done
log "host suites done"
for _ in $(seq 1 720); do pgrep -f "docker build -t tensorfold-qwen38" > /dev/null || break; sleep 20; done
cd "$HOME/work/target" || exit 1
for arm in a b; do
  dir=$R/$(echo $arm | tr a-z A-Z)
  log "build r2$arm from $(ls "$dir"/*.patch | wc -l) patches in $dir"
  ./build_patches.sh "r2$arm" git://192.168.99.16/up-pr/tf "$BASE" "$dir" > "$R/build-r2$arm.log" 2>&1 ||
    { log "BUILD r2$arm FAILED"; tail -20 "$R/build-r2$arm.log" >> "$R/chain.log"; exit 1; }
  ~/work/lanes/fp4port/relabel.sh "tensorfold-qwen38:r2$arm" embedded >> "$R/chain.log" 2>&1 ||
    { log "RELABEL r2$arm FAILED"; exit 1; }
  log "built r2$arm"
done
cells=()
for c in 1 2 4 6 8; do cells+=("A1:$c:r2a" "B1:$c:r2b" "B2:$c:r2b" "A2:$c:r2a"); done
log "window queued: ${cells[*]}"
bash "$R/win/win.sh" "$R/win/w1" "${cells[@]}"
log "window finished"
python3 "$R/win/sum.py" "$R/win/w1/window.log" >> "$R/chain.log" 2>&1
touch "$R/CHAIN-DONE"
