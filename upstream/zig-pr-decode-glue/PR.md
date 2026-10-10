# Upstream PR (not posted): patches/0019: decode read-outs fused, up projection + mix and reduce + activation

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w5-opus (`~/work/lanes/w5-opus/`, image `w5-opus-final`, holds hold5-hold8), merged image `zw5b` (`merge/mverify8.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0019: decode read-outs fused, up projection + mix and reduce + activation (decode +0.5 to +1.2%, replies byte-identical)

**Body:**

## Description and Motivation

A graphed one-stream round (34.2 ms, ~1,552 kernels) has 2.43 ms (7.1%) in which no weight-streaming kernel
runs: the gaps between kernels (0.53 ms) and the hyper-connection read-outs' small glue kernels (`_reduce` 0.39 ms,
`_hc_writeback` 0.27, `_hc_normed` 0.15, `_hc_act` 0.12, `_hc_mix` 0.11, ...; nsys `--cuda-graph-trace=node`).

`patches/0019-flash-next-decode-readout-fusion.patch` fuses two pairs of them in decode windows:

- `TF_FLASHNEXT_UPMIX_DECODE` (on unless `0`): each layer's read-out runs the up projection and the mix as one
  `_hc_up_mix` launch at decode widths, the BM 32 Triton variant already in the kernel set (prompt chunks already use
  the BM 64 one). Not the final mixer's read-out (its 32-group sums of `mixed` feed the 4-bit MTP draft matrices),
  not 1-row windows (the kernel set has no M = 1 variant), two-rank runs or recorded-launch tests.
- `TF_FLASHNEXT_REDUCE_ACT` (on unless `0`): `tf_fn_hc_reduce_act_kernel` (`fn_ops.cu`) replaces bf16 `_reduce` (the
  split `_b16mm`'s fp32 K slices, summed in slice order) and `glue._hc_act`. It repeats the Triton kernels' SASS
  operation for operation (`v * 0.25` for `v / S`, `cvt.rn.bf16`, `0 - v`, `* 1.4426950216293334961f`,
  `ex2.approx.f32` without ftz, `+ 1`, `div.full.f32`). It does not write `act`'s 32-group sums: only the 4-bit MTP
  matrices read them, and the fusion is off when those are loaded.
- `glue-check` also runs the reduce-act check and the up-mix check at 2-16 rows (before `wbNormCheck`, which stops on
  the stock kernel set at a variant it lacks). The boot log says `decode read-outs: ...` for each one engaged.

Why the replies do not change: `_hc_up_mix` is the kernel set's own kernel, the same `mixed` bytes as `_b16mm` +
`_hc_mix` (the prompt path relies on that already); the fused reduce + activation computes Triton's operations in
Triton's order.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Merged build with this patch's reduce + activation added alone (`zw5b`; the up-mix was already in), two boots an
arm after a warm-up, tok/s:

| | before | with the fused reduce + activation |
| --- | ---: | ---: |
| code, 1 / 2 / 4 clients | 126.9 / 89.1 / 63.6 | 128.2 / 89.7 / 63.9 |
| prose, 1 / 2 / 4 clients | 72.4 / 59.6 / 39.7 | 72.8 / 60.3 / 39.9 |

+0.5 to +1.2% in all six cells. The up-mix alone (lane image against the stock engine, hold5): code +0.6 / +0.6 /
+0.8%, prose +0.9 / +0.9 / +0.3% at 1 / 2 / 4 clients; both together in the engine (`bench-many`, hold6, every run
above every base run): code +1.0% at 1 stream and +1.1% at 4, prose +1.7% and +0.9%. The fused kernel takes 2.4-2.5 us
against 4.1-4.8 us for the two launches.

Measured and left out (with their switches): an L2 prefetch of the next weights on a side stream during the glue (the
weight kernels got faster, the latency-bound glue beside them slower by as much: no gain) and forking the shared expert
before the router (within noise).

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here.
- `glue-check`: the reduce-act check EQUAL on 134 cases (random fp32 bit patterns with NaN, inf and subnormals,
  exponents 2^-140 to 2^100, cancelling sums, the split `_b16mm`'s own partials; 1-128 rows; with and without the
  inject rows); `_hc_up_mix` EQUAL at 2-16 rows for BM 32 and 64 on every fill. Mutants: the slice order reversed in
  the fused kernel gives 44 DIFFER; an up-mix that leaves the last row unwritten gives golden 3/6.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR], #[0015's PR], #[0016's PR], #[0017's PR], #[0018's PR] merged first (logically it needs none of them). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
