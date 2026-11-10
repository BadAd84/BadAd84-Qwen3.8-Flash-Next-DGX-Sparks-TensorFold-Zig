# TensorFold 1.2.6 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.6 (`6e9af930261a88bb28ac0bfb157ce8e57e9eea07`) and every
change we own is one numbered patch here, applied in filename order. This is the artifact the image build
consumes: `build_patches.sh TAG git://192.168.99.16/up-pr/tf 6e9af9302 <this directory>`.

Applied in order, the 27 patches touch 85 paths and reproduce the `stacked126` development branch exactly
(that branch is the same series as commits, kept for history).

| patches | lever |
|---|---|
| 0001-0003 | the copy window: 64-row capability, the pending-row log falling back to the row-by-row DeltaNet path, the boot self-check that serves the largest row-exact width (48 rows on the NVFP4 checkpoint) |
| 0004 | copy re-sync past an edit and the lone copy ramp in shared rounds |
| 0005-0009 | `--kv-cache fp8` for Flash Next: the e4m3 attention caches, the KV8 device code, the compile and launch-record fixes, the lean-gate pass |
| 0010 | the n-gram row cache and read-ahead: `TF_FLASHNEXT_GATHER_READ=pread`, parked readers, the draft-ahead read, the evened prompt tail |
| 0011 | a shared pass gathers every stream's n-gram rows in one pool call and locks the tables' scales |
| 0012-0013 | prompt passes drain less, fill 3072-row chunks, route MXFP8 projections to the relaxed tile (default off) |
| 0014-0016 | the relaxed 128 x 128 prompt tile and its two-stage, two-blocks-an-SM variant (`TF_FLASHNEXT_PROMPT_GEMM2`), and the sm_12x launch records |
| 0017-0019 | the MTP draft head's 4-bit rows by default |
| 0020-0023 | prompt passes' native hyper-connection read-out as two fused kernels, the hcn fatbin split, the plan and dims declarations, the roce row and split test flag |
| 0024 | the hyper-connection read-outs from a lossless 12-bit copy of their weights (`TF_FLASHNEXT_HC_Q12`) |
| 0025 | a shared round priced from the environment (`TF_FLASHNEXT_ROUND_MS`, `TF_FLASHNEXT_DRAFT_ROW_MS`) |
| 0026-0027 | vision: ModelOpt NVFP4 and MXFP8 tower linears decode to bf16 at load, and a request's image rows may reach 16,384 |

## Applying

```
git clone --no-checkout <repo> tf && cd tf
git fetch origin 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 && git checkout --detach FETCH_HEAD
for p in /path/to/patches/1.2.6/*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done
```

Every patch is a fact about the code it changes; the commit message in each carries the reason and the
measurement. Settings these patches add are read through `zig/src/platform/environment.zig`, so each has a
row there and the build refuses an unregistered CUDA switch.
