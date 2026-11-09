# levers124 - the campaign levers stacked on 1.2.4 (267c5af6a), as toggleable patches

Generated 2026-11-09 from the `levers124-stack` branch on spark6 (`~/work/lanes/stack124/tf`, fresh clone
of Gitea `ots/tensorfold-levers124`). The stack branch cherry-picks each lever's code commits onto
`267c5af6a` (Release 1.2.4) in the campaign's value order; these .patch files are that stack squashed to
one patch per lever (the granular 20-commit history is on the pushed `levers124-stack` branch, the
squashed 11-commit form on `levers124-series`). Numbering continues the recipe's
`patches/0017-draft-chain-running-product-stop-rule.patch`. All 11 apply in this order on a pristine
`267c5af6a` (verified by `git apply --check` + byte-identical tree compare against the series branch).

Apply order = the order below. Every knob the levers add is off/unset by default (off = stock 1.2.4
behaviour), except the two defaults the campaign measured as wins: the 48-row self-check floors the
served width at the largest row-exact width it finds (upstream 32 on checkpoints that do not verify at
48), and the draft head's rows load 4-bit by default (`TF_FLASHNEXT_DRAFT_HEAD=exact` restores upstream).

| # | lever | source branch @ tip (base) | measured |
|---|---|---|---|
| 0018 | warm turns | `port-warm-turns` @ 877faca4 (267c5af6a) | next-turn TTFT -38-45% (recipe 6.6) |
| 0019 | 48-row copy window | `port-64rows-v3` @ 93475cf7e (267c5af6a), receipt-only commit excluded | verbatim copy 374.3 -> 473.7 tok/s (+26.6%), one-word rewrite +12.2%, edits and plain decode flat (48-row receipt, both arms) |
| 0020 | copy re-sync + shared ramp | `resync-on-48rows` @ b212b9f4 (48-row head), receipt-only commit excluded | one-word rewrite 230.5 -> 300.2 tok/s (+30.2%), two concurrent edits +41.7/+49.3%, edit-beside-prose 148.9/47.8 -> 234.8/50.2 on the ab4b2f05 pair (0064); re-measurement on the 48-row base in flight (`resync48` lane) |
| 0021 | draft-head 4-bit reader | `port-0005-reader` @ d6197769 (267c5af6a), changelog-only commits excluded | code +7.3/+4.1/+6.5/+9.6% and prose +9.9/+2.9/+4.6/+9.7% at s1/2/4/6, model memory 76.16 -> 75.89 GiB (reader124 A/B, 12 ABBA cells, golden 6/6) |
| 0022 | kv-cache fp8 | `port-0003-kv8` @ 7ff8292bc (c5a044877) | ~17.5 KiB/token caches vs 30 KiB, five full-window streams where bf16 admits three; golden byte-equality is the storage-only check (A/B window was queued) |
| 0023 | prefill speed | `port-0006-prefill` @ fea018cc7 (e5889236b) | A/B window queued (gates green on its lane: fmt, pr_check 0/0, host suite 1 new failure found and fixed) |
| 0024 | n-gram gather, one pool call | `port-0010-ngram` @ 81d9995f4 (its own newer-main base) | interim receipt only (gates green, ATC clean); A/B pending |
| 0025 | n-gram row cache + pread | `port-0013-pread` @ 2bcac6708 (its own newer-main base) | its lane's window build FAILED (`pread13 rc=1`) - needs a rebuild before its PR; carried in the stack so the stacked A/B exercises it |
| 0026 | shared-round round cost | `port-0009-cost` @ 88c8920d (f212eeabd) | A/B window queued (TF_FLASHNEXT_ROUND_MS / TF_FLASHNEXT_DRAFT_ROW_MS unset by default, so off = stock pricing); stacked-tree gates below |
| 0027 | MX128 prompt tile two-stage + contract records | `port-0015-mx128` @ c747816f (f212eeabd); its tile kernels and `TF_FLASHNEXT_PROMPT_MX128` rule came in with 0023 (upstream 0006 bundles the tile), so 0027 is the two remaining commits | both new knobs off by default; stacked-tree gates below |
| 0028 | stack repairs (fp8/pread files compile) | own repair commit a4a956cea on the stack | eight defects those two levers landed in files no gate had compiled: the fp8 glue's three unused `Glue` parameters, `attnChunksOn`'s shared-byte count typed past its launch, the row cache's duplicated import block, its `Ngram` handed by value where the reader takes a pointer, ple's shard bound named privately, the row cache test's two opens discarding the reader they then unwrap, the snap sizing's missing `Kv` import and two-argument `attnBytes`, the paging batch test's `Fake` without the fp8 calls the batched pass routes to, and the draft head's KV rows restored to a window of rows (the kv-cache squash had priced and allocated one position's) |

Conflict resolutions made while stacking 0026/0027 (the earlier ones are below):
- `zig/src/platform/environment.zig` / `environment_test.zig`: both sides' rule/case sets concatenated
  again (0009's `.text` kind and its two rules, 0015's `TF_FLASHNEXT_PROMPT_GEMM2` rule and case).
- `zig/src/families/flashnext/cuda_lanes.zig` was already at the 600-line lean cap: kept 0009's
  `round_costs` import and 0025's `ple_cache`, and made room by dropping the dead `train` import and
  inlining the single-use `living` and `ple_cache` imports at their call sites (600 exactly).
- `zig/src/cuda/qmmf.zig`: kept both test blocks (the base's instance-name test and 0015's two-stage
  shared-bytes test).
- `zig/src/core/contract/qmmf_prompt_records.zig` (created upstream after 267c5af6a, absent from the
  base): the four MXFP8 prompt launch records land in `flashnext_tile_records.zig`'s `cuda` array
  instead, with their nvcc-13.0 usage and `later_pending`; the upstream-only file is not carried.

Conflict resolutions made while stacking (all reviewed against the base's own layout):
- `zig/src/families/flashnext/cuda_lanes.zig` `Options`: kept the warm-turns constants and added 0003's
  `kv8: bool = false` field.
- `zig/src/core/contract/registry_joins.zig` (created upstream after 267c5af6a, absent from the base):
  the KV8 launch records register in the base's `registry.zig` `landed_cuda` chain instead, beside the
  other flashnext pendings; the upstream-only file is not carried. The kv8 lever's own final commit had
  reduced `flashnext_kv8_pending.zig` to its header while the chain kept importing its records, which
  0028 repairs by restoring the four records the fp8 lane measured.
- `zig/src/families/flashnext/cuda_knobs.zig` (created by both 0006 and 0010/0013 upstream-side): merged
  into one module holding the prompt knobs, the gather knobs and the row-cache reader knobs.
- `zig/src/platform/environment.zig` / `environment_test.zig`: both sides' rule/case sets concatenated
  (no duplicates).
- `zig/src/families/flashnext/cuda_lanes.zig` prompt rows: kept the base's `*Lane` argument to
  `passRows` and adopted 0013's `tailRows` second step.
- `zig/src/families/flashnext/cuda_ple.zig`: kept 0010's `maybeLockScales` and added 0013's
  `openCache` read-ahead line above it.
- `zig/src/native/cuda_snaps.zig`: the warm-turns switch folded into `zig fmt` shape.
- `CHANGELOG.md`: the base's Unreleased section carries each lever's own bullet; upstream-main bullets
  between 267c5af6a and the newer lever bases (tool-call ids, Metal, DeepSeek heads, ...) are NOT part
  of this stack and are excluded.

Gates on the final stack (base 267c5af6a vs head): `zig fmt --check` clean;
`tools/pr_check.py --base 267c5af6a --pr 9999`; host suite in
`nvcr.io/nvidia/pytorch:26.07-py3` with the stock-267c5af6a failing list diffed (stock three: listener
Nagle + two drama_voice). Results: `~/work/lanes/stack124/results-gates.log` on spark6.
