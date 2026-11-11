# TensorFold 1.2.6 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.6 (`6e9af930261a88bb28ac0bfb157ce8e57e9eea07`) and every
change we own is one numbered patch here, applied in filename order. This is the artifact the image build
consumes: `build_patches.sh TAG git://192.168.99.16/up-pr/tf 6e9af9302 <this directory>`.

Applied in order, the 30 patches touch 85 paths and reproduce the `stacked126` development branch exactly
(that branch is the same series as commits, kept as the tag `archive/stacked126`).

| patches | lever | buildable prefix? |
|---|---|---|
| 0001-0005 | the copy window: 64-row capability, the pending-row log falling back to the row-by-row DeltaNet path, the boot self-check that serves the largest row-exact width (48 rows on the NVFP4 checkpoint), the single-line comment fixes, the layout-test pins | yes (verified compile) |
| 0006 | copy re-sync past an edit and the lone copy ramp in shared rounds | with 0007-0012 |
| 0007-0011 | `--kv-cache fp8` for Flash Next: the ported kernels, glue, batch, draft, prompt and snapshot, the KV8 device code and its compile and launch-record fixes | with 0012 |
| 0012 | the kv8 integration: the glue, snapshot and prompt corrections that only apply once the kv8 code exists, the kv8 launch records measured for this tree, and the fp8 test's new argument | yes (verified compile) |
| 0013 | the n-gram row cache and read-ahead | with 0014-0015 |
| 0014 | a shared pass gathers every stream's n-gram rows in one pool call and locks the tables' scales | with 0015 |
| 0015 | the pread reader integration: the duplicated prelude, `Reader.create`'s scope, the reader import and `max_shards` | yes (verified compile) |
| 0016-0017 | prompt passes drain less and fill 3072-row chunks, and the relaxed MXFP8 prompt tile defaults off | after 0030 |
| 0018-0019 | `TF_FLASHNEXT_PROMPT_GEMM2` and its sm_12x launch records | after 0030 |
| 0020-0021 | the MTP draft head's 4-bit rows by default | after 0030 |
| 0022-0025 | prompt passes' native hyper-connection read-out as two fused kernels and its fatbin split | after 0030 |
| 0026 | the hyper-connection read-outs from a lossless 12-bit copy of their weights | after 0030 |
| 0027 | a shared round priced from the environment | after 0030 |
| 0028-0029 | vision: ModelOpt NVFP4 and MXFP8 tower linears decode to bf16 at load, and image rows may reach 16,384 | after 0030 |
| 0030 | the remaining integration tail: the draft files reverted to upstream, the tile kernels' fields, the parity test's argument, and the relaxed tile's default | full series only |

## Applying

```
git clone --no-checkout <repo> tf && cd tf
git fetch origin 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 && git checkout --detach FETCH_HEAD
for p in /path/to/patches/1.2.6/*.patch; do git apply --whitespace=nowarn "$p" || exit 1; done
```

Every patch is a fact about the code it changes; the message in each carries the reason and the measurement.
Settings these patches add are read through `zig/src/platform/environment.zig`, so each has a row there and the
build refuses an unregistered CUDA switch.

## State (2026-11-11, overnight)

The series builds `tensorfold-qwen38:stack126` from a pristine `6e9af9302` (30 patches apply with `git apply`;
`zig build fatbins install native` passes in nvcr.io/nvidia/pytorch:26.07-py3 with zig 0.17.0). The image boots
through the campaign recipe with `KV_DTYPE=fp8` or `bf16`, `TENSORFOLD_CUDA_KERNELS=native` (the image's own Triton
AOT set is refused beside Flash Next's glue), and serves requests whose replies are byte-identical to stock's at
the 16-token probe (sha 9b3560a2...).

Defects found and fixed in the integration patches (0012 and 0029) while bringing it up (each found by a boot or a request, not by a test):

1. `e.graphs = .{}` had been replaced by the kv8 hunk's `e.kv = .bf16`, so the graph caches were undefined memory
   and the first graph use panicked ("incorrect alignment").
2. The kv8 hunk had also re-priced the draft head's caches as a single fp8 row; upstream sizes them
   `sizes.kvBytes(cap, head_heads)` (bf16) for both key and value. The first kept prompt state's copy overran a
   1,024-byte cache (cuMemcpyDtoDAsync invalid value) and a kernel then faulted.
3. The draft files now stay upstream's exactly (cuda_mtp_draft.zig, cuda_mtp_ops.zig reverted), because the
   refusal text is right: the draft head's caches are bf16 beside any sequence format. The pread read-ahead wiring
   and the tests' extra argument were dropped with that revert; TF_FLASHNEXT_DRAFT_AHEAD is therefore not wired
   into the draft pass yet (it still drives the n-gram warm reads), noted for the pread lever's next round.
4. The other compile-level corrections (duplicate prelude, Reader.create scope, missing imports, unused
   parameters, q12 template deduction, tile kernel fields, kv8 launch records measured with cuobjdump, the fp8
   test's pg argument) are listed in the integration patches' messages. The kv8-only ones sit in 0012, which
   means rows plus kv8 is itself a buildable prefix (verified by a container compile), and the rest sit in 0029.

Open: the boot self-check reports 0 of 2080 rows row-equal on the full stack (the rows-only image reports widths
1-48 and serves 48-row windows), so the stack falls back to upstream's 32 rows. The prime suspect is a prompt-pass
lever that changes summation order (the fused hyper-connection read-out or the prompt tiles), which the self-check
would correctly reject; the next round A/Bs those knobs with the check on. Also open: `--parallel 8` at 262,144
tokens is refused on the memory estimate (36.31 GiB of streams against 27.41 GiB left), where the 1.0.0 stack fit
8 streams in 24.14 GiB.
