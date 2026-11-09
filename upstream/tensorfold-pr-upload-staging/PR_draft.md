Title: cuda: stage blocking H2D uploads through an anonymous buffer

## What this changes

`DeviceBuffer.upload` passes the caller's mapping straight to the copy. On a 64K-page kernel (DGX
Spark kindling spark-os), a blocking H2D copy whose source is a file-backed mapping - the safetensors
checkpoint is loaded through an mmap - issues a driver ioctl that never completes: the boot spins
forever in kernel time with zero syscalls, at the checkpoint-load phase, on every launch. The same
build on a 4K-page DGX OS kernel has never reproduced it, which is why it has not surfaced upstream.

This stages every blocking upload through a 1 MiB anonymous stack block: the copy reads from anonymous
memory (which the driver handles) and the file-backed mapping is only ever touched by the CPU. No new
settings, no API change; non-blocking uploads are untouched.

- Issue: n/a, this is a boot-correctness fix on 64K-page kernels; the bytes copied are identical.
- Stacked on: main.
- Overlap: [ATC - filled before posting]

## Reproduction and fix evidence

- Before: the checkpoint-load phase spins at 100% kernel time indefinitely (measured ~20 min without
  progress, single core, zero syscall progress); the serve never reaches /health. Reproduces on every
  boot on one NVIDIA GB10 running spark-os with 64K pages (kernel 7.0.0-1019, driver 580.178.04 in
  forward-compat over CUDA 13.3 userspace). Does not reproduce on DGX OS (4K pages) on the same GPU.
- After: five consecutive boots complete the same load in 59-83 s and reach /health, on the same box,
  same checkpoint (the INT4 AutoRound checkpoint at its pinned rev), same 1,048,576-token window
  config. The fix also holds on the FP4 checkpoint (the NVFP4 arms boot and pass their probes).
- Exactness: the boot-time golden comparison is 6/6 identical to the stock reference on the INT4
  checkpoint, and the exactness probes pass on every arm - the staging changes which memory the copy
  reads from, not the bytes copied.

## Checks on this head

- Base: [BASE]; head: [HEAD]. Both arms built from the same tip with the fatbins.
- `tools/pr_check.py --base origin/main`: [GATES]
- Host suite: [SUITE]
- Kernel contract: no GPU kernel changes (the copy path is host-side staging).
- Not run: Metal, HIP and XPU host tests (the measurement box is CUDA only).

## Checklist

- [x] The title and description match the head commit and the reproduction.
- [x] No new settings; unset behaviour is exactly today's.
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits.
- [x] No precision traded for speed: the staged copy moves the same bytes.
