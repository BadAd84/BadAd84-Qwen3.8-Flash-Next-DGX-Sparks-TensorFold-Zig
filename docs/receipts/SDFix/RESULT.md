# SDFix: patch 0008's shared-direct write-back, fixed, gated and priced

## 1. The package

`patches/main-1ece6e6db-r4`, base `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. r3's 0008 was byte-identical to r2's
(`10688fa54b7b50c75f9687a41cc4f00409801bb3d04265295e57d10b17e32612`), so this is 0008's first change since r2; r4's
0008 is `86610c97cbd6fe1268029bba1b1e33fd0a468d70d27693d9cbc15808d3664989`. The four edits:

- `zig/kernels/cuda/flashnext_hc.cu`: `hc_writeback_norm` (line 128) gains the `MODE == 3` branch (line 153, the same
  arithmetic as `hc_writeback`'s mode 3 at line 81); `fn_hc_writeback_norm_moe_sh` is instantiated at line 206 as
  `hc_writeback_norm<3, 10, 4>`.
- `zig/src/families/flashnext/cuda_glue.zig`: `wbn_moe_sh` beside `wbn_moe` (field line 42, loaded line 148) and the
  `3 =>` case in `hcWritebackNorm` (lines 531-537).
- `zig/src/families/flashnext/cuda_batch_hc.zig:71`: the `pass.shared_direct` branch of `writebackNorm` calls
  `hcWritebackNorm(..., 3, 10, 11, 1)` instead of the norm-less `hcWriteback`.
- Tests: `contract_flashnext_wbnorm.zig` gains the `moe_sh` mode (11, 31, 37, 71, 103-105, 144-148): `prepare` puts
  the shared fp32 row in the last slot (the copy `fn_shared_scatter` makes), `theirs` runs the same fused launch in
  mode 2, and gate 1's rule plus gate 3 compare HOUT, PSS and NORM byte for byte; `contract_flashnext_more.zig:27`
  widens the set to `[4]`.

`0020` re-pins `flashnext_hc.cu` (`f420761f...` -> `02887175...`) and `cuda_glue.zig` (`f9cc870b...` -> `6e33cea6...`).
The other 18 patches are byte-identical to r3's (cmp on all 20). `CHANGES.md`, `README.md` and `RECORD.md` carry the
difference, the mechanism and the device result.

No host test exists for this writeback: `hcWritebackNorm` returns `error.NativeGlueRequired` without the native glue
(`cuda_launch.zig:390-393`) and `Glue.load` refuses a host-only build (`cuda_glue.zig:117`). The contract entry and the
boot gate are the pins.

## 2. Host gates (Paperclip, `paperclip.ots-int.net`, x86-64, no GPU)

One run, `~/work/SDFix/gates.sh`, under `~/work/host.lock`, from a base extracted out of `in/base.tar.gz` and verified
against `in/ls-tree.z` (`12601 blobs, 0 missing, 0 mismatch, 0 extra, 0 mode_bad`) and a repo rebuilt at the exact
base commit (`tree 3a37e287...`, `HEAD 1ece6e6db...`), then the package's own `apply.sh`:

| gate | rc | wall | evidence |
|---|---:|---:|---|
| `apply.sh --check` | 0 | 0 s | 20 patches apply |
| `apply.sh` | 0 | 1 s | 20 patches applied |
| tree against `r4-series.manifest` | see note | | the run's check counted `.git` as extras; the same check on the device tree (no `.git`) read `12621 entries, 0 mismatches, 0 extra_files` |
| status changes | 0 | 0 s | 94 modified, 20 new |
| `pincheck.py` base / applied | 0 / 0 | 0 s | `files 169 failing 0` on each |
| `zig fmt --check build.zig zig` | 0 | 2 s | |
| `cuda_common_check.py` | 0 | 0 s | |
| `cuda_fragment_check.py` | 0 | 1 s | |
| `git diff --check` | 0 | 0 s | |
| `lean_check.py` base / head | 1 / 1 (soft) | 2 s / 2 s | 168 / 231 problems, the series' own style findings |
| `lean_new.py` r3 tree vs r4 tree (local) | 1 | 78 s | `1 new`: `flashnext_hc.cu: over 600 lines` (598 -> 610); everything else inherited |
| `test-environment-host` | 0 | 3 s | 28/28 tests |
| `test-gradient-serving` | 0 | 3 s | 1/1 |
| `test-qwen-serving-host` | 0 | 0 s | 2/2 |
| `test-kernel-contract -Dfixed-cpu` | 0 | 294 s | 260/260 |
| `compile-config-server -Dtarget=aarch64-linux-gnu` | 0 | 233 s | 8/8 |
| `compile-cuda-tests -Dtarget=aarch64-linux-gnu` | 0 | 171 s | 10/10 |
| `compile-cuda-tests -Dnvcc` | 0 | 596 s | 168/168 |
| `compile-cuda-tests -Dnvcc -Dtarget=aarch64-linux-gnu` | 0 | 715 s | 168/168 |
| `fatbins install native -Dnvcc -Doptimize=fast` | not observed | | still running when the budget stopped the session |

Note: after that run, the contract's gate-1 rule string was corrected to name its actual baseline (mode 2's fused
launch), a test-only change; the final package was verified from scratch (`apply.sh`-equivalent 20/20, v20 vs v21
file-for-file, `compare_trees.py`: 12,621 files, 0 differ) but its own `fmt`/`test-kernel-contract`/`nvcc_runner`
re-run (`delta.sh`) was not executed before the budget stop. The engine sources are unchanged by it.

## 3. The device proof (spark6, image `tensorfold-qwen38:sdfix-r4`, `sha256:46d47005...`)

Image built from the r4 tree inside the container (base verified by `ls-tree.z`, the applied tree by
`r4-series.manifest`: `12621 entries, 0 mismatches, 0 extra_files`), relabelled `embedded`. Contract, exactly as run:

```
(filtered) SUMMARY 4 kernels: 4 pass gates 1-4, 0 fail, 0 known findings; 0 controls: 0 red as planted, 0 missed; 0 limit problems; gates 255 ms, limits 0 ms
PASS nonfinite cuda flashnext fn_hc_writeback_norm_moe_sh (...): the stated rule holds: the written rows, their 256-column square sums and the normalized rows bit-equal to the two launches
PASS repeat cuda flashnext fn_hc_writeback_norm_moe_sh (...): five runs byte-identical (41120 bytes), inputs and guards untouched, no overlap
PASS shapes cuda flashnext fn_hc_writeback_norm_moe_sh (...): 3 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
```

(The rule sentence in that log is the pre-correction text; the comparison itself is mode 3 against mode 2's fused
launch, as `theirs` computes. The corrected string was not rebuilt on device before the budget stop.)

The 20-item oracle, exact text hashes against `in/ref20.json`, every boot's environment read back and diffed with an
empty result, image id gated on every boot:

| arm | delta | verdict | exact | marker | gold |
|---|---|---|---:|---:|---:|
| CTRL (pre-fix r3 image, defaults) | none | BROKEN | 0/20 | 3 | 1 |
| SD1A (r4) | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` | RESTORES | 20/20 | 20 | 20 |
| SD1B (r4) | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` | RESTORES | 20/20 | 20 | 20 |
| SD0 (r4) | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` | RESTORES | 20/20 | 20 | 20 |
| FUSE0 (r4) | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1`, `TF_FLASHNEXT_HC_FUSE=0` | RESTORES | 20/20 | 20 | 20 |

## 4. The lever's measured value (same fixed build, two boots an arm, orders alternating)

Cold TTFT, thinking off, idle, medians of three samples a boot:

| case | lever on (boots) | lever off (boots) | on vs off |
|---|---|---|---:|
| cold 8k | 3.632, 3.669 (mean 3.651) | 3.693, 3.697 (mean 3.695) | **-1.2%** |
| cold 32k | 14.791, 14.755 (mean 14.773) | 14.918, 14.913 (mean 14.915) | **-1.0%** |

Decode, aggregate tok/s, mean of two passes a boot, mean of the two boots:

| cell | on | off | on vs off |
|---|---:|---:|---:|
| C1 prose | 63.08 | 63.13 | -0.1% |
| C1 code | 81.57 | 81.82 | -0.3% |
| C8 prose | 228.86 | 231.49 | -1.1% |
| C8 code | 339.41 | 335.29 | +1.2% |

Decode is flat within its cell noise. The lever's prefill value on the fixed build is about a fifth of the 4.6-4.9
percent it was credited with on the broken build: most of that gap was the NORM work the broken mode-3 branch never
did. The fixed lever still buys 1.0-1.2 percent of cold prefill at these sizes, so the mitigation was lifted.

## 5. Production restored

The window's EXIT trap stopped its serve and started production from `~/qwen6-start-prod.sh` with
`IMAGE=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`. Its own line:

```
prod /health 200 (start rc 0) image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f 2026-11-22T06:23:10+00:00
```

`docker inspect` then read `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea...` and `/health` 200.

Commits (signed, local, not pushed):

- `d273fab49` `patches: main-1ece6e6db-r4, 0008's shared-direct write-back writes NORM` (26 paths, the package);
- `e84e85db8` `Qwen3.8 dev: re-enable the shared-direct prompt lever on the fixed write-back` (the dev.env line that
  supersedes `fb7f905e`), made because the oracle read 20/20 at all three settings and the contract passed.

## 6. What this does not prove

- The rebuilt-image verify (final tree: contract string corrected) did not run; the device contract and oracle ran on
  the image above, whose only difference from the final tree is that one printed rule string in a test file, plus
  the package docs. The final package's own delta gates (`fmt`, `test-kernel-contract`, `nvcc_runner`) were not run.
- `fatbins install native` on Paperclip and its record audit did not finish inside the budget.
- The new symbol is not in the kernel contract's launch-usage registry (`flashnext_tile_records.zig`), so gate 5 does
  not audit its registers/static bytes; its three siblings' records pass, and the launch mirrors them (256 threads,
  the same grid and template).
- One checkpoint (nvfp4), one device (GB10, sm_121), one image, one 20-item set, 1,330-1,494 prompt tokens. Decode
  cells use the harness's short prompts; the lever's route applies to prompt passes only.
- The no-delta control is the r3 image, so the reference validity is shown in-window; the 0/20 answer set on that
  control is the same record PatchBisect and PromptFid measured.
