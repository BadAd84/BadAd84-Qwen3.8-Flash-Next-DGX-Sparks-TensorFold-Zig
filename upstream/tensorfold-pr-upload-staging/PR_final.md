Title: minimax: route the vision tower's checkpoint upload through DeviceBuffer.upload

## What this changes
`minimax_m3/cuda_vision.zig` Tower.up passes checkpoint mmap bytes straight to the driver:
the copy's source is a file-backed mapping, and on a 64K-page kernel (DGX Spark kindling spark-os)
the driver ioctl issued from that mapping never completes - the boot spins at 100% kernel time, zero syscalls, at the vision tower's load. `DeviceBuffer.upload`
is the repo's own staging path for exactly this (the same convention `radio/weights.zig` line 175
already follows); this change routes the tower's upload through it. No new settings, no API change;
the bytes copied are identical.

A sweep of every `cuMemcpyHtoD_v2` site on main found no other live defect-class caller.

- Issue: n/a, this is a boot-correctness fix on 64K-page kernels; no arithmetic moves.
- Stacked on: main
- Overlap:
- Overlap: `atc overlap --json`: changedFiles 2; 4 hard conflicts (PRs 2665, 2585, 2619, 2260) all
  `CHANGELOG.md`-only, none touching the code file; 6 clean shares; the board snapshot is partial
  (`pullFilesLimit`).

## Reproduction and fix evidence

- Before: a boot with a minimax vision checkpoint spins indefinitely at the tower load (100%
  kernel-mode time, no syscall progress) on one NVIDIA GB10 running spark-os with 64K pages (kernel
  7.0.0-1019, driver 580.178.04 in forward-compat over CUDA 13.3 userspace). Does not reproduce on
  DGX OS (4K pages) on the same GPU.
- After: base and head boot the same checkpoint through the vision tower load in 34 s each (three
  consistent A/B passes) and reach /health; the fix is the staging, nothing else differs.
  Golden 6/6 identical between base and head on every pass - the staged copy moves the same bytes.

## Checks on this head

- Base: `23b69e25e` (current main); head: `9bee291f0`. Gitea branch `fix-upload-staging`.
- `tools/pr_check.py --base origin/main`: 0 errors, 0 warnings; lean base-vs-head 398 vs 398, 0 new
  (each side with its own copy of the checker).
- Host suite (`nvcr.io/nvidia/pytorch:26.07-py3`, zig 0.17.0, no GPU, `--network none`): base and
  head failing lists byte-identical - the stock three environment failures - and the four non-unit
  CI steps green on the head tree:
  kernel-contract 236/236, golden 5/5, security 31/31, fuzz 21/21.
- Testability: not CPU-testable - the Tower needs CUDA module loads and there are no minimax
  fixtures; the staging mechanism it routes to is covered by the suite, and the fix itself was
  boot-proven on the 64K-page kernel (the A/B above). Stated rather than skipped silently.
- Kernel contract: no GPU kernel changes (host-side staging only).
- Not run: Metal, HIP and XPU host tests (the measurement box is CUDA only).

## Checklist

- [x] The title and description match the head commit and the reproduction.
- [x] No new settings; unset behaviour is exactly today's.
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits.
- [x] No precision traded for speed: the staged copy moves the same bytes.