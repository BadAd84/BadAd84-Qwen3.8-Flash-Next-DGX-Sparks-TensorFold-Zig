---
name: tensorfold-lever-campaign
description: "Run a lever campaign on an upstream TensorFold tip: port, prove byte-identity, measure 1/2/4/6 with a boot-split ABBA, record negatives, stage PR texts - on a shared dev Spark"
---

# Lever campaign on an upstream TensorFold tip (GB10 dev Spark)

Proven end to end 2026-11-07/08 on spark6 (kindling 64K, NVFP4, bf16 KV): five levers ported or measured
onto stock TensorFold 1.2.4, every cell byte-identical, two PR texts staged. The procedure below is the
distilled workflow; the SSOT record is `docs/FP4-PORT-AND-RETEST.md` sections 6-6.5 in
qwen3.8-flash-next-dev.

## Setup

- Upstream clone `~/work/lanes/up-pr/tf`; one worktree per lever:
  `git -C ~/work/lanes/up-pr/tf worktree add -b port-<lever> ~/work/lanes/port124X/tf <tip>`.
  One lever = one branch = one PR; never stack two levers on a branch.
- Check the real tip (`git ls-remote https://github.com/ashhart/TensorFold main`) - a local mirror lies.
  BOTH A/B arms must come from ONE tip (a receipt pairing a rebased head with a stale-base stock arm
  measures nothing and gets re-run).
- Build: `cd ~/work/merge && ./build-br.sh TAG git://192.168.99.16/<lane>/tf <FULL 40-char sha>` (the git
  daemon on 192.168.99.16:9418 serves `~/work/lanes`), then relabel:
  `echo "FROM tensorfold-qwen38:TAG" | docker build -q --label tf.kernels=embedded -t tensorfold-qwen38:TAG -`
  - without it the recipe's `start.sh` refuses the image and the smoke "failure" is a label error, not code.

## GPU window protocol (shared dev ring)

- Announce the window on the coordination channel BEFORE starting; per-lane `RUNS_DIR` (rows accumulate
  across boots of the same cell dir - the #1 summariser bug); per-lane sparkDash timer name; refuse to
  start over a foreign pending timer.
- Stop sparkDash from the session that holds the proxmox key (spark6 cannot reach proxmox):
  `ssh root@192.168.99.100 'pct exec 111 -- systemctl stop sparkdash'`; then stop the serve, kill the
  lock holder, `flock -o ~/work/gpu.lock` for the whole window; on EVERY exit path restore the serve
  (`setsid nohup ~/qwen6-start.sh ...`, prove /health) and start sparkDash - only when the lock is free.
- Write scripts to files and run them detached (`setsid nohup`); never inline a multi-minute pipeline
  behind one ssh timeout. Never write `arm.sh` in place while any boot is in flight (bash reads it
  incrementally - a mid-boot write voids the cell); new arms go in lane-owned copies.

## Cells and measurement

- Arms: NVFP4 (`CHECKPOINT=nvfp4`), vision off, bf16 KV (the 1.2.4 Flash Next family refuses
  `--kv-cache fp8`; INT4-AutoRound is refused outright: `UnsupportedCheckpoint`), 131,072-token windows,
  `HOST=127.0.0.1`, loopback-only; levels 1/2/4/6 (8 streams do not fit at bf16 KV: 32.86 vs 31.41 GiB -
  state the refusal, never drop the row silently).
- Boot-split parsing: rows accumulate per (kind, pass) group; verify group counts per file before quoting
  any median. Golden 6/6 vs the stock arm's OWN replies (an older-interval reference differs by quant).
- Probes: `tfm_decode.py` (every slot busy), `ttft.py`, the copy/rewrite/edit workloads (zcopy.py,
  w2copy.py) - a decode-lever's real signal is in the copy/rewrite cells, not plain decode.
- GPU temp per window; SOURCES line 127.0.0.1 only; request counts equal between arms.

## Gates (upstream CONTRIBUTING)

`zig fmt --check`; `tools/zig/lean_check.py` run on BASE and HEAD trees each with its own copy (compare
counts, not one tree); host suite in the base image with failing-test LISTS compared (v1.2.4 has 3
pre-existing env failures: a listener test needing a network, two drama_voice_tool tests expecting
EACCES as root); files <= 600 lines; single-line comments <= 120 columns; mutants in a scratch copy with
the unmutated copy scored first. The host suite NEVER compiles .cu - a fatbin compile gate is required
for any kernels change (a missing instantiation only shows at boot as `CUDA_ERROR_NOT_FOUND`).

## Known traps (each measured)

- The 64 KiB-page boot hang is a pageable H2D copy sourced from the file-backed safetensors mmap
  (DeviceBuffer.upload chokepoint); upstream >= 1.1.4 fixes it via copy custody (`copy_source.zig`
  syncChunk). NOT the CUDA 13.3 compat lib - all images share it and the oldest boots kindling with it.
- A 3-way merge can drop explicit instantiation lines and macro heads in .cu files silently; the host
  suite never sees it; only the image build or a boot shows it. Gate on removed `TF_*` lines plus an
  nvcc fatbin compile of every changed .cu.
- Mangled kernel-name tails are hand-copied: pin every symbol array with a test, and grep that no
  `sym.ld_*` lookup resolves through the wrong module handle.
- Generated files (`fn_qmmf_ld.cu` by `tools/zig/flashnext_qmmf_ld.py`) carry a FOOTER that must gain
  every new instantiation, or a regeneration deletes them.
- An `exact_width`/row-count change needs a boot-time self-check over the real weights with automatic
  fallback to upstream's shape (the 48-row boundary was found this way; 49+ rows differ because the
  pending-row log holds `batch.late_rows = 48`).
- A settings port's old optimum does not transfer: re-measure every knob on the new tip (the
  CONFIDENCE -0.15/-0.3 wins on INT4 became 2.5-9% losses on NVFP4 1.2.4).
- A negative result is a result: record it (the 12-bit hc read-out was flat on 1.2.4) so the lever is
  never retried, and state the variance honestly (plain decode bounded ~+-2% across boots, not
  "no regression").
