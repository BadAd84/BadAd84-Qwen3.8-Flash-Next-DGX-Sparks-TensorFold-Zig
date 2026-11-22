# `main-1ece6e6db-r5-kvtier`: provenance, base and the gates it passed

## What this is

One patch, `0021-kv-tier-fp8.patch`, added on top of `patches/main-1ece6e6db-r5` (0001 to 0020). It is cut against
r5's tree, so r5's twenty patches are byte-identical here and the pair applies in filename order.

- **Repository and base**: upstream TensorFold `main`, `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` (2026-11-20
  13:01 UTC, "changelog: #4202 under Unreleased"), plus `patches/main-1ece6e6db-r5` 0001 to 0020.
- **Source of the change**: our own work, not an upstream import. The design is `work/KvTierRecon/DESIGN.md`
  (window 1 readiness checklist, section 11.5, items 1 to 5 and 7, and item 12's doc line); the code is written
  against r5's tree by us. Nothing is copied from another project.
- **We edited**: yes, all five files, by us.
- **Base for a rebuild**: apply r5 then this patch to a pristine checkout at the base above, or build the tree the
  host proved the patch reproduces (`work/KvTierW1`, `head.tgz`, 12,622 files).

## The patch's shape

| file | + / - |
|---|---:|
| `zig/src/families/flashnext/cuda_disk.zig` | +62 / -26 |
| `zig/src/native/cuda_kept.zig` | +2 / -2 |
| `zig/src/native/cuda_kept_test.zig` | +40 / -0 |
| `zig/src/native/cuda_disk_policy_test.zig` | +4 / -0 |
| `docs/recipes/flash-next-cuda.md` | +4 / -3 |

## Checks

| check | result |
|---|---|
| `apply.sh --check` on a pristine worktree at the base | `the series and 1 KV-tier patches apply on 1ece6e6dbb... in order (nothing written)` |
| the applied tree against the gated tree, file for file (12,622 files) | `PATCH-REPRODUCES-HEAD` |
| `zig fmt --check build.zig zig` | rc 0 |
| `zig build -Dfixed-cpu test-environment-host` | rc 0 |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | rc 0 |
| `zig build -Dfixed-cpu test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | rc 0 |
| `zig build -Dfixed-cpu test-kernel-contract` | rc 0 |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | rc 0 |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | rc 0 |
| `zig build -Dfixed-cpu test` (the umbrella, where the family module's own tests run) | rc 0; the base tree's umbrella also rc 0, with 0 named failures either side |
| `tools/zig/cuda_common_check.py` | `cuda common: 55 local copies, 0 violations` |
| `tools/zig/cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses` |
| `pincheck.py` over `zig/tests/fixtures/gradient-serving.tsv` | `files 170 failing 0` |
| the lean pair, each side's own `lean_check.py`, `lean_new.py` on (file, message) | `lean: 230 problems, 230 on the base, 0 new` |
| the lean control, base's copy run from the head cwd | 230 problems, so each tool scanned its own root |

Every gate ran on Paperclip (x86-64, Zig 0.17.0) under `~/work/host.lock`. Three rounds: the first found two defects
of ours (a shadowed `t` in a test fixture, a 122-column comment), the second a third (`cuda_disk_policy_test.zig`'s
Flash Next fixture left `engine.kv` undefined, and `facts` now reads it, so a `switch` over it panicked), the third is
green on all of the above.

## The device result (spark6, 2026-11-22)

The image `tensorfold-qwen38:kv-w1`, `sha256:ef6967ac57fb40a19f0c54c4788ac1e9f79fb73cf29b61ba3f19090a961108bb`, built
from the gated tree (`label=embedded`, `patches-label 4144696f21e3`), one hold of `~/work/gpu.lock`:

- the r5 control image refused the same boot line with `error: Fp8KvUnsupported`;
- fp8 wrote `imprint: 6813 tokens on disk: 26 new blocks and its own 113 MiB (232 MiB this state, 119 MiB of rows it
  shares) in 294 ms`, and after a restart read it back with `imprint: read 6813 tokens from disk (232 MiB in 76 ms)`,
  answering with a 0.113 s prefill against 2.947 s cold (0.195 s ttft against 2.952 s);
- a bf16 boot into the same directory opened its own identity (`/cache/kvtier/fp8/45f377096735c545` against the
  fp8 arm's `b6112c6ee454c245`), logged no `imprint: read`, and served the same token ids as a fresh pass;
- the write's cost to the first request was 63 ms (2.947 s against 2.884 s with no `--prompt-cache-disk`).

`work/KvTierW1/RESULT.md` has the arm logs, the byte arithmetic against DESIGN's 4.72 GiB (which is the
262,144-token figure; the 6,813-token state is 244,270,976 bytes) and what remains for window 2.
