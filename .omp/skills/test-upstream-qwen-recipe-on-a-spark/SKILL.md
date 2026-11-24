---
name: test-upstream-qwen-recipe-on-a-spark
description: "Run a stock upstream qwen/TensorFold recipe build on a Spark for A/B or PR verification, including the kindling-64K boot wall and DGX OS rollback."
---

# Test an upstream qwen/TensorFold recipe on a Spark

Use when verifying an upstream recipe PR or stock build on our DGX Sparks (e.g. reproducing a
maintainer re-test). Our production stacks carry the 64K-kernel loader fix; stock upstream builds
do not, so they DO NOT BOOT on kindling spark-os. Plan the box and OS first.

## 1. Pick the OS: stock engines need DGX OS (4K), not kindling (64K)

- Kindling 64K boot-failure signature (all upstream stock builds tested): container starts, engine
  pegs ONE core at ~99% CPU, GPU counter parks at ~2.7-2.8 GiB, API never answers; no error output
  because the engine's stdout is buffered and only flushes at death.
- To read the engine's last words: `docker kill <name>` (NOT `docker rm` - rm destroys the log), then
  `docker logs <name>`.
- Switch: `ssh -A adam@sparkN 'sudo sparkos-rollback'` -> DGX OS 7.6 (GRUB entry 0) and reboots.
  Return after the test: `sudo sparkos-rollback 0.9.5-1019-64k` (exact name from `ls /boot/sparkos/`;
  TRIAL=0 in entry.conf = promoted, becomes the default again). Same command works from both OS
  sides. Needs the forwarded YubiKey agent (owner present for the sudo/touch).
- Verify with `getconf PAGESIZE`: 65536 = kindling, 4096 = DGX OS. Docker images, /home (checkpoints,
  clones, kernel caches) survive both switches.

## 2. Boot traps on a cold cache

- **Vision helper boot-loop**: on a fresh kernel-cache hash, the vision helper's one-time first-boot
  compile outlasts the engine's internal VisionTimeout, the engine exits ("the helper stopped before
  it was ready (VisionTimeout)"), and every retry starts over. Workaround: `VISION=0` for text-only
  A/Bs (state it in any write-up). The compile does NOT persist (container-local), so waiting does
  not help.
- start.sh env passthrough is generic: every `TF_FLASHNEXT_*` var in the launching shell reaches the
  container; default arms need `env -u TF_FLASHNEXT_CONFIDENCE`.
- `WAIT_TIMEOUT` (default 1800) bounds start.sh's API wait; a failed boot blocks that long unless
  you set it lower (600 works for healthy boots).

## 3. What is already on spark6

- Recipe clone `~/qwen-zig` (upstream main fetched); experiment worktree `~/qwen-stock`.
- HF cache holds both checkpoints: nvidia/Qwen3.8-Flash-Next-FP4-Local @b9ce18a6 (96G) and
  azampatti INT4-AutoRound @14642741 (122G) - CHECKPOINT=nvfp4|int4 selects them, no downloads.
- prepare.sh builds locally when GHCR pull is unavailable (~5 min, same tag scheme as the campaign
  image - a rebuild REPLACES `tensorfold-qwen38:zig-db28187`).
- A/B runner pattern that worked: ABBA per checkpoint, fresh boot per arm, one streams-1/64-token
  warm-up, GPU temp sampled before/after every bench window, bench via `tools/bench_streams.py
  <url> --decode-only --streams 1,2,4 --tokens 512 --reps 3`.
- Stop sparkDash during arms (`ssh root@proxmox.ots-int.net "pct exec 111 -- systemctl stop
  sparkdash"`) and restart it after.

## 4. Comparing with upstream re-tests

Upstream re-tests (e.g. plotarmordev on the qwen recipe) run stock main on stock-DGX-OS-class boxes;
absolute numbers differ from ours (checkpoint/config/env), so compare DIRECTIONS and within-run
ratios, and name our run conditions (VISION, PARALLEL, PRODUCT_STREAMS, DEPTH, checkpoint) in any
PR comment. Post as BadAd84 via `gh pr comment N --repo ... --body-file` (gh is authed on Adam's
box).
