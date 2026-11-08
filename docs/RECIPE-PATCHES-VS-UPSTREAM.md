# Answer: are the recipe's 17 patches already covered by upstream code?

Checked against upstream `267c5af6a` (the tip our A/B arms ran) and today's tip `303c389d4a`,
by content probes on the Flash Next family and kernel files, plus `git apply --check` of each
patch against both tips.

## Short answer

**No - upstream carries the MECHANISM for only 3 of the 17, and none of them are the same code.**
Upstream has equivalents for 0003's fp8-KV-adjacent machinery, 0017's stop-rule *concept*, and
0012's late-log constant - but 14 of 17 patches target files whose Flash Next kernel/zig structure
upstream does not have (the recipe's own `flashnext_*.cu` kernel set is a different layout from
upstream's), and the content probes for the specific features come back empty.

## Per patch

| patch | feature | upstream 1.2.4 | evidence |
|---|---|---|---|
| 0001/0002 | NVFP4 vision tower + 16k image tokens | **no** - `zig/src/vision/` has no NVFP4/nvidia-tower loader; upstream serves vision from a different path | 0 hits for nvfp4/mxfp8 in the family; the recipe's 0001 touches 10 files incl. `docs/vision.md` |
| 0003 | `--kv-cache fp8` for Flash Next | **no** - the family keeps bf16 (measured live: the 1.2.4 build refuses `--kv-cache fp8`) | grep: no KV_DTYPE/kv8 in the family |
| 0004 | prompt expert tile + `contract_controls.cu` | **no** - `contract_controls.cu` does not exist upstream | key-file check: 2/2 missing |
| 0005 | fp8 attention reader keeps the next tile in registers, MTP head cache 4-bit rows | **no** - 0 hits for `next_tile` in `flashnext_attn.cu` | content probe |
| 0006 | prefill: no drain between chunks, vectorised hc kernels | **no** - no drain knob in `flashnext_hc.cu` | content probe |
| 0007 | sampled requests join the batched draft pass | **partly** - 1 hit for "sampled/join" in `cuda_lanes.zig`, but the batched-head mechanism is the recipe's | needs a boot probe |
| 0008 | GPU top-k candidates for sampled drafts | **yes, a top-k exists** (1 hit in `flashnext_mtp.cu`) - whether it is the same 3x-faster kernel needs a bench | content probe weak |
| 0009 | round-cost model (`TF_FLASHNEXT_ROUND_COST`) | **partly** - upstream has round-cost *timing* (`batch_costs.zig`, `drafts_cost.zig`) but the recipe's allocation-side cost model is in `core/lanes/allocate.zig` which upstream lacks | key-file check: 2/2 missing |
| 0010 | n-gram rows of all lanes gathered in one pass | **no** - the gather is per-lane upstream | key-file check |
| 0011 | host draws on worker threads + faster candidate kernel | **no** - draws on the host per row (the 1.1.0-era shape) | key-file check: `cuda_host_draw.zig` missing |
| 0012 | partly-rejected draft window: rollback folded into the next verify (`KEEP_LATE`) | **no** - `batch.late_rows = 48` is the log-capacity constant, not the folding; the folding mechanism (`cuda_batch_lanes.zig` KEEP_LATE block) is absent | content probe: 0 hits |
| 0013 | n-gram `pread` read-ahead + chunk-tail rule | **partly** - `pread` exists (15 files, 23 hits) but the recipe's chunk-tail rule is in `cuda_batch.zig`/`cuda_lanes.zig` hunks that do not apply | apply --check fails |
| 0014 | prompt hc fusion (`flashnext_hcf.cu` new) | **no** - `flashnext_hcf.cu` does not exist upstream; `hc.fuses` handles attention/mlp fusion, not the prompt form | key-file check |
| 0015 | prompt MX128 two-stage tile (`qmmf.cu` rework) | **no** - 0 hits for mx128/two-stage in the family | key-file check |
| 0016 | shared expert side stream + lane-batched DeltaNet | **no** - `cuda_batch_side.zig` new; `SHARED_SIDE` 0 hits; GDN one-launch is `cuda_batch_kernels.zig`/`cuda_launch.zig` (upstream's own form, measured +3-6%) | key-file + content probe |
| 0017 | running-product stop rule (`mtp.confidenceFor`, PRODUCT_STREAMS) | **partly** - `draft_confidence` (a floor) exists in `core/lanes/config.zig`, and the windows' `nodeChances` doc mentions the running product, but `confidenceFor`/`PRODUCT_STREAMS` do not exist; the recipe's own 0017 measured it as a fix for 1.2.4 treating negatives as never-stop | key-file + content probe |

## Why the probes and the apply-check agree

Every one of the 17 patches fails `git apply --check` against both `267c5af6a` and today's tip
(`303c389d4a`), for the same structural reason: the recipe's series was written against a
`flashnext_*.cu` kernel layout that upstream never had - upstream's own Flash Next kernels are a
different set (`flashnext_attn_lanes.cuh`, `flashnext_gdn_lanes.cuh`, `flashnext_hcf.cu` missing, etc.).
So "covered" would require the feature to exist in upstream's OWN structure, and the content probes show
it does not for 14 of 17.

## What this means for the campaign

- The recipe's 17 patches are a genuine porting backlog for any 1.2.4-based serve that wants the recipe's
  measured numbers; they do NOT come free with upstream.
- Our two new levers (0064/0065) were written directly against upstream 1.2.4, so they do not stack on
  the recipe's series - they stack on upstream. If both worlds are wanted, the recipe series and our
  levers need a common base decision (either port the recipe series to 1.2.4 as the maintainer is doing,
  or run upstream + our levers as the fork/patch set).
- The 0016/0017 features (shared-expert side stream, running-product stop rule) exist in upstream only
  as the maintainer's own re-implementations noted in the recipe's CHANGELOG - so for THOSE two, the
  recipe patches are the duplicate, not upstream.
