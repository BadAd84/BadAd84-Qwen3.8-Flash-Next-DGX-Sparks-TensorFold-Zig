# TensorFold 1.2.6 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.6 (`6e9af930261a88bb28ac0bfb157ce8e57e9eea07`) and every
change we own is one numbered patch here, applied in filename order. This is the artifact the image build
consumes: `build_patches.sh TAG git://192.168.99.16/up-pr/tf 6e9af9302 <this directory>`.

Applied in order, the 28 patches touch 85 paths and reproduce the `stacked126` development branch exactly
(that branch is the same series as commits, kept as the tag `archive/stacked126`).

| patches | lever |
|---|---|
| 0001-0005 | the copy window: 64-row capability, the pending-row log falling back to the row-by-row DeltaNet path, the boot self-check that serves the largest row-exact width (48 rows on the NVFP4 checkpoint), the single-line comment fixes, and the layout-test pins |
| 0006 | copy re-sync past an edit and the lone copy ramp in shared rounds |
| 0007-0011 | `--kv-cache fp8` for Flash Next: the ported kernels, glue, batch, draft, prompt and snapshot, the KV8 device code and its compile and launch-record fixes (0007's commit message still says "ported onto 1.2.4", stale from the port; reworded when that lever's PR is assembled) |
| 0012 | the n-gram row cache and read-ahead: `TF_FLASHNEXT_GATHER_READ=pread`, parked readers, the draft-ahead read, the evened prompt tail |
| 0013 | a shared pass gathers every stream's n-gram rows in one pool call and locks the tables' scales |
| 0014-0015 | prompt passes drain less and fill 3072-row chunks, and the relaxed MXFP8 prompt tile defaults off |
| 0016-0017 | `TF_FLASHNEXT_PROMPT_GEMM2`: the relaxed prompt tile runs two stages and two blocks an SM, and its sm_12x launches are registered |
| 0018-0019 | the MTP draft head's 4-bit rows by default, with its changelog line |
| 0020-0023 | prompt passes' native hyper-connection read-out as two fused kernels, the hcn fatbin split, the plan and dims declarations, the roce row and the split test flag |
| 0024 | the hyper-connection read-outs from a lossless 12-bit copy of their weights (`TF_FLASHNEXT_HC_Q12`) |
| 0025 | a shared round priced from the environment (`TF_FLASHNEXT_ROUND_MS`, `TF_FLASHNEXT_DRAFT_ROW_MS`) |
| 0026-0027 | vision: ModelOpt NVFP4 and MXFP8 tower linears decode to bf16 at load, and a request's image rows may reach 16,384 |
| 0028 | the 1.2.6 integration fixes: the pread reader's imports and constructor scope, the three attention helpers' unused parameter, the q12 call's template deduction, the snapshot tail's format, the tile kernels' fexp_up and hc-fuse bench launches, the kv8 contract records measured for this tree, and the fp8 test's new pg argument. The tree compiles `zig build fatbins install native` clean |

## Applying

```
git clone --no-checkout <repo> tf && cd tf
git fetch origin 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 && git checkout --detach FETCH_HEAD
for p in /path/to/patches/1.2.6/*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done
```

Every patch is a fact about the code it changes; the message in each carries the reason and the measurement.
Settings these patches add are read through `zig/src/platform/environment.zig`, so each has a row there and the
build refuses an unregistered CUDA switch.
