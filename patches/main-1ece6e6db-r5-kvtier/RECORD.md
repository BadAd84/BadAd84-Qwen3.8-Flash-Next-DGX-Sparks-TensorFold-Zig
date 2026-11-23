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

## 0022 (the append dedup), 2026-11-23

- **Repository and base**: upstream TensorFold `main`, `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, plus
  `patches/main-1ece6e6db-r5` 0001 to 0020 and `0021-kv-tier-fp8.patch` (byte-identical here). 0022 is cut against
  the 0021 tree and applies after it in filename order.
- **Source of the change**: our own work, not an upstream import. The attribution is `work/KvTierW5/RESULT.md`
  section 2 (the append write amplification measured on spark6); the code is written by us against the 0021 tree.
- **We edited**: yes, both files, by us.
- **Shape**: 2 files, +52 / -2 (`zig/src/core/prompt_cache.zig` +9 / -2, `zig/src/core/prompt_cache_rewind_test.zig`
  +43 / -0).
- **The tree the package reproduces**: a fresh worktree at the base + `apply.sh` (the series, then 0021 and 0022) is
  file-for-file identical to the gated tree (12,622 files, sha256 listing diff empty). The same worktree with the
  series and 0021 alone (`pre`) is byte-identical to window 1's gated tree (`work/KvTierW1/tree`, 12,622 files,
  0 diff), so the lean base and the before/after test sit on the artifact window 1 gated.
- **The test is the before/after witness**: on `pre` with only the new test file copied in, `zig build -Dfixed-cpu
  test-prompt-cache-host` fails with `slices differ ... instead found [0]: 8 [1]: 13` (706/707 passed, rc 1); on the
  0022 tree the same step is rc 0.

Checks (Paperclip, x86-64, Zig 0.17.0, under `flock ~/work/host.lock`, from freshly extracted staged trees whose
sha256 were verified both ways):

| check | result |
|---|---|
| `zig fmt --check build.zig zig` | rc 0 |
| before/after: `zig build -Dfixed-cpu test-prompt-cache-host` on `prefail` | rc 1, the new test only (`PREFail-OK`) |
| `zig build -Dfixed-cpu test-prompt-cache-host` | rc 0 |
| `zig build -Dfixed-cpu test-cache-store-host` | rc 0 |
| `zig build -Dfixed-cpu test-learn-recovery` | rc 0 |
| `zig build -Dfixed-cpu test-environment-host` | rc 0 |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | rc 0 |
| `zig build -Dfixed-cpu test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | rc 0 |
| `zig build -Dfixed-cpu test-kernel-contract` | rc 0 |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | rc 0 |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | rc 0 |
| `tools/zig/cuda_common_check.py` | `cuda common: 55 local copies, 0 violations`, rc 0 |
| `tools/zig/cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses`, rc 0 |
| `pincheck.py` over `zig/tests/fixtures/gradient-serving.tsv` | `files 170 failing 0`, rc 0 |
| the lean pair, each side's own `lean_check.py` | base 7014 files / 230 problems, head 7014 / 230 |
| `lean_new.py` on (file, message) | `lean: 230 problems, 230 on the base, 0 new`, rc 0 |
| the lean control, `pre`'s copy run from the head cwd | 7014 files / 230 problems (each tool scanned its own root) |
| `zig build -Dfixed-cpu test` (the umbrella) | rc 0 |

The gate log is fetched to the laptop (`work/KvTierDedup/ev/gates-ev.tgz`, sha256
`2acedc28af3962780e86c7f0a98440e3e7531d39f435a3430b6e4911423ce7ea`). `failed command:` lines appear inside steps
whose rc is 0 (child-process output interleaved into the log); every verdict quoted here is the step's rc.

## The device result (spark6, 2026-11-23)

Image `tensorfold-qwen38:kv-dedup`, `sha256:2f0f1c5a7d0492679f56fd06eb4884a21d92baf42f6568eb25af37d05cb96b9f`, built
on the box from the gated tree (`tf.patches 4144696f21e3`, `tf.kernels embedded`, the docker compile 479.7 s), one
hold of `~/work/gpu.lock`; the baseline arm is `tensorfold-qwen38:kv-w1` (`sha256:ef6967ac...`, window 1's image).
Both arms: NVFP4 checkpoint, fp8 KV, one slot at 262,144 tokens, `--prompt-cache-disk` with
`--learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20`, production's own 53-variable environment.

Window 5's 100,000-word conversation, seeded in one boot (3,168,781,592 B, 2.95 GiB, the same on both arms), then
five fresh-boot appends per arm, one greedy request each, the store's own file set read before and after:

| arm | turn | resumed at | TTFT s | prefill s | kept | added bytes | MiB |
|---|---:|---:|---:|---:|---:|---:|---:|
| new | 6 | 105,202 | 1.032 | 0.327 | 1 | 121,954,256 | 116.3 |
| new | 7 | 105,272 | 1.297 | 0.576 | 2 | 242,454,924 | 231.2 |
| new | 8 | 105,632 | 1.049 | 0.330 | 1 | 120,463,540 | 114.9 |
| new | 9 | 105,705 | 1.035 | 0.320 | 1 | 121,841,336 | 116.2 |
| new | 10 | 105,778 | 1.068 | 0.332 | 1 | 118,349,556 | 112.9 |
| old | 6 | 105,202 | 1.102 | 0.399 | 2 | 238,564,436 | 227.5 |
| old | 7 | 105,272 | 1.245 | 0.540 | 2 | 242,454,924 | 231.2 |
| old | 8 | 105,632 | 1.084 | 0.382 | 2 | 240,358,896 | 229.2 |
| old | 9 | 105,705 | 1.099 | 0.394 | 2 | 238,263,060 | 227.2 |
| old | 10 | 105,778 | 1.126 | 0.407 | 2 | 236,094,824 | 225.2 |

- **The bytes roughly halve where the fix applies**: 115.1 MiB a turn (120,652,172 B, the mean of turns 6, 8, 9 and
  10) against 228.1 MiB (239,147,228 B) on `kv-w1` and the recorded 227.5 MiB baseline. New turn 6 is window 5's
  M1b figure to the byte (121,954,256 B); old turn 6 is X1's to the byte (238,564,436 B).
- **Turn 7 is the boundary, and it does not halve**: after a 320-token reply the rewind sits 331 tokens above the
  resume, over `min_gap` (256), and both arms write 242,454,924 B. The condition, not a defect.
- **TTFT and depth**: turn 6 resumed at 105,202 (the recorded depth) in 1.032 s TTFT / 0.327 s prefill, against the
  recorded M1b 1.068 s / 0.358 s and `kv-w1`'s 1.102 s / 0.399 s. The no-tier cold twin of the same prompt is
  46.716 s.
- **Exactness**: five of five resumed replies equal their no-tier cold twins' token ids and prompt tokens (sha16
  `277412fd297b56aa`, `af913cc499e378a6`, `1b6cdb6c046cd2c6`, `fadbe9183c3f5d09`, `505b2cc22424a0d7`), and the
  two arms' replies are equal to each other on all five turns. Turn 6's hash is window 5's recorded cold hash for
  the same prompt as well.
- **Disk arithmetic after the fix**: 115.1 MiB an append turn; a 100-turn 100k session 14.1 GiB (was 25.0 GiB); a
  60 GiB budget holds 508 append turns (was 257); the 200 GiB daily ledger about 1,754 appends (was 884).
- **Production restored**: `PROD-IMAGE-OK sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`,
  `/health` 200. Stores (7.69 GiB) and scratch removed; `/home` 119 GiB free at the restore line, 126.5 GiB after
  the cleanup. Evidence: `work/KvTierDedup/ev.tgz` (sha256
  `8fb7ea2729e0bf99274a7b538c2ab519c9e0eeb74067a3df3e89751cfd8c3541`); the window's report is
  `work/KvTierDedup/RESULT.md`.
