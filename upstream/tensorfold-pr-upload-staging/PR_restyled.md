Title: minimax: route the vision towers checkpoint upload through DeviceBuffer.upload

---

What this changes:
`minimax_m3/cuda_vision.zig` Tower.up passes checkpoint mmap bytes straight to the driver:
the copy's source is a file backed mapping, and on a 64k page kernel (DGX spark kindling spark-os)
the driver ioctl issued from that mapping never completes - the boot spins at 100% kernel time,
zero syscalls, at the vision towers load. DeviceBuffer.upload is the repos own staging path
for exactly this (see same convention radio/weights.zig line 175) and this change routes the
towers upload through it.
No new settings, no api change; bytes copied are identically.
Sweep of all `cuMemcpyHtoD_v2` sites on main found no other live defect class caller

- Issue: n/a - this is a bootcorrectness fix on 64k-page kernels. No arithmetic moves
- Stacked on: main
- Overlap:
    - `atc overlap --json`: changedFiles = 2, 4 hard conflicts (PRs 2665, 2585, 2619, 2260) all
      CHangelog.md only, none touching the code file. 6 clean shares. Board snapshot is partial
      (`pullFilesLimit`)

---

Repro fix evidence:

-   <before> - A boot with a minimax vision checkpoint spin infinitely at towers load (100%
    kernel time, zero syscalls) on one NVIDIA GB10 running spark-os with 64k pages (kernel
    7.0.0-1019, driver 580.178.04 in forward compat over CUDA 13.3 userspace).
    Does not repro on DGX OS (4k pages) on the same GPU
-   <after> - base and head can both boot towers checkpoint through the vision towers load in
    34s each of three consistent A/B passes, reach /health.
    The fix is the staging, nothing else has changed. Golden 6/6 identical between base and head
    on every pass (staged copy moves same bytes).

---

Checks on this head:

-   Base: `23b69e25e` (current main) Head: `9bee291f0` Gitea branch:
    `fix-upload-staging`
-   `tools/pr_check.py --base origin/main` 0 errors, 0 warnings
    lean base-vs-head is 398 vs 398 0 new (each side has its own copy of the checker).
-   Host suite (`nvcr.io/nvidia/pytorch:26.07-py3`, zig 0.17.0, no gpu `--network none`): Base
    and head failing lists byte identical - same 3 environment failures as always and suite
    only 4 non unit CI steps green on the head tree:
        -   Kernel contract 236/236
        -   Golden 5/5.
        -   Security 31 / 31
        -   Fuzz 21/21
-   Testability: not cpu testable (tower needs cuda module loads, no minimax fixtures), staging
    mechanism it routes to is covered by suite and fix itself was boot proven on 64k page
    kernel <a/b above>. Stated rather than skipped silently.
-   Kernel contract - no gpu kernel changes (host side staging only).
-   Not run:
        -   Metal
        -   HIP
        -   XPU
        -   host tests

---

Checklist:

-   [x] Title and description match head commit and repro
-   [x] No new settings, unset behaviour is exactly todays.
-   [x] Comments and docstrings are one liner. No measurements or history in the source/
-   [x] No personal data, machine names, internal hosts or local paths in the diff or its commits.
-   [x] No precision for speed: staged copy moves same bytes.