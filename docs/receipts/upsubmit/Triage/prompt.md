# Prompt path triage: 0005 (drain, 3,072-row chunks, relaxed MX128) and 0006 (MX128 two-stage)

Triage base is upstream main **T = `077998f7d9b14adebec3a2acc2caa47ff7ae6ec7`**, "changelog: #3572 under Unreleased",
committed 2026-11-16 15:26:10 +0000, from `timeout 90 git -C work/upmain fetch origin main`. Every check below is
against T, not against the series base `964174ea05`.

Worktrees: `work/Triage-prompt` (pristine T, per-hunk `git apply --check`) and `work/Triage-prompt-b` (series-order
check). Both `git worktree add --detach` at T. Nothing was compiled, no GPU job ran, nothing was published.

## Verdicts at a glance

| item | verdict | one line |
|---|---|---|
| 0005, the chunk drain removal | **SPLIT, SUBMIT candidate (rank 1)** | exact by construction (no kernel, no arithmetic); 16 insertions in 5 files (`prA-nodrain.patch`); measured -7.8% cold 64k at C>=2 in one receipt, flat in two others |
| 0005, `default_chunk` 1536 to 3072 | **SPLIT, SUBMIT candidate (rank 2)** | exact if `splitK`'s row independence holds (upstream states it in code); raises the scratch bound from under 2 GiB to under 5 GiB and adds 1,536 rows to every lane's prompt_rows admission; measured bundled with the drain, never alone |
| 0005, the relaxed MX128 MXFP8 prompt tile | **RETIRE from upstream** | it re-orders the prompt sums by construction; the patch's own CHANGELOG says "they are not the exact kernels' bits"; no token-equality receipt and no FP64 reference; `docs/pr/SKILL.md:74` bans a mode that changes output tokens even opt-in |
| an exact MXFP8 128-row tile (new work, not in 0005) | **HOLD: build it, measure it** | the tile geometry without the relaxed arithmetic; bytes equal to the 64x64 MXFP8 instance by construction; unmeasured and register-tight |
| 0006, the two-stage `PROMPT_GEMM2` tile | **RETIRE from upstream** | it is the relaxed tile with a different pipeline depth, so it inherits the ban; and upstream already ships a two-blocks-an-SM prompt tile (the BF16 K32 staging) |

No patch in this lane carries what upstream's kernel contract asks for. Details below.

## 1. What upstream already has at T

- **A 128 x 128 BF16 prompt tile, exact.** `qmmf.cu:202-210` instantiates
  `qmmf_kernel<BF16, 128, 128, 2, 4, 3, ...>` four times (bf16/fp32 out, plain/fused slices). `prompt_shared` is
  98432 bytes (`zig/src/cuda/qmmf.zig:157`), one block an SM on sm_12x. CHANGELOG line 732 (entry #1846): "with the
  same output bytes, so cold prompts take 3.7 to 4.4% less time on a GB10 ... and replies are unchanged.
  `TF_FLASHNEXT_PROMPT_BF16=0` turns the tile off".
- **A K32 staging of that tile, exact and two blocks an SM.** `qmmf.cu:214-245`: `PromptK32Tile` with
  `static_assert(SMEM == 49152)`, `__launch_bounds__(256, 2)`, "keeps the parent's packed weights, K16 MMA chain and
  final output rounding". CHANGELOG line 720 (entry #1848): "with the same output bytes and replies". The commits are
  `ec76abd45` (larger BF16 prompt tiles with exact outputs), `c3acc3466` (K32 staging), `fbf8d960d` (only where it
  pays).
- **The tile's selection gates.** `promptEligible` (`qmmf.zig:174-178`) requires `m >= prompt_rows` (512),
  `w.mode == .bf16`, `w.n >= 128`, `(w.k >= 512 or (n == 10240 and k == 320))` and `w.npad % 128 == 0`;
  `usesPrompt` (`qmmf.zig:269-274`) adds `!p.cluster and !p.reduce` and `2 * promptBlocks(m, w.n) > l.prompt_sms`.
  MXFP8 weights are excluded: they take `qmmf_kernel<MXFP8, 64, 64, 1, 4, 4, ...>` (records at
  `zig/src/core/contract/registry.zig:62,64,77,79`, dynamic 49664, 128 threads).
- **A row-count-independent K split.** `splitK` (`qmmf.zig:42-49`) is documented "from the shape alone so a row's
  bits never depend on the row count", and `planSlices` picks `fused` at `m >= fused_rows` (256) with the slice order
  fixed (0, 1, 2, ... same as `reduce_kernel`'s loop).
- **The drain 0005 removes.** `zig/src/families/flashnext/cuda_prompt.zig:404-414`: a while loop issues
  `p.chunk(...)` per chunk and then `if (hooks.logits == .none) try e.complete();`; `complete` is
  `stream.synchronize()` (or the collective's finish) at `cuda_prompt.zig:343-346`.
- **The chunk default.** `default_chunk: usize = 1536` (`zig/src/families/flashnext/cuda_batch_state.zig:56`), read
  through `cuda_chunk.zig` (`TF_FLASHNEXT_CHUNK`, `TF_FLASHNEXT_CHUNK_SOLO`), and `cuda_lanes_load.zig:23` sets the
  engine's chunk to `soloRows(chunkRows(), one_stream and tp == 1)`, so a one-stream server takes 8192-row passes and
  a multi-stream server takes `default_chunk` rows whether or not a second stream is active.
- **The rules the verdicts rest on.** `docs/pr/SKILL.md:74`: "TensorFold takes no lossy weight or cache formats, even
  opt-in, and no mode that changes output tokens, even opt-in. Output must stay token-equal to the serial
  reference." `CONTRIBUTING.md:79`: "Prompt chunks and decode use the required row arithmetic, with recurrent state,
  KV and final logits checked at seams." `CONTRIBUTING.md:84`: "A changed reduction order needs an independent FP64
  reference for each affected projection class ... Report worst per-column differences." `CONTRIBUTING.md:114`: "with
  token hashes equal on the default path. An opt-in that changes tokens says so and shows its proof." The
  maintainer's own constraints on issue #3368 (comment 2026-11-14, read with `gh api repos/ashhart/TensorFold/issues/3368/comments`):
  "Default path exact ... same sums, same order", and "Kernels go in the kernel contract with a float64 reference of
  the stored weights, a planted control that the contract must catch, and the CUDA `SUMMARY` line", and "Receipts on
  current main from your GB10: main against the branch, alternating arms, a fresh server each run, with both commits
  named", and "any change that would move a default path token is one we will ask about before taking it".

## 2. Patch 0005 (`patches/main-964174ea05/0005-prompt-chunk.patch`)

203 insertions, 11 files: `qmmf.cu` +137, `qmmf.zig` +33, `cuda_knobs.zig` +14, `cuda_tiles.zig` +8, `cuda_batch.zig`
+6/-2, `cuda_prompt.zig` +6/-1, `cuda_batch_state.zig` +1, `environment.zig` +2, `environment_test.zig` +3,
`cuda_startup_test.zig` +1/-1, `CHANGELOG.md` +2. It carries **three behaviours**: the chunk drain, the 3,072-row
default chunk, and the relaxed MXFP8 128 x 128 prompt tile.

### 2.1 Applies on T?

No, not as one patch, and not through the series. 18 hunks in 11 files: **14 apply on T, 4 do not.**

Applied cleanly on T: the whole `qmmf.cu` kernel block (the two new kernels and the namespace split), all four
`qmmf.zig` hunks (shared bytes, the `prompt_mx` field, `loadPrompt`'s two function loads, `matmulPrompt`), both
`cuda_batch.zig` hunks (`tiles.matmul(..., self.hooks.prompt)` and the scratch test's bound), `cuda_batch_state.zig`
(`1536` to `3072`), the two other `cuda_prompt.zig` hunks (the `prompt_mx_min_n` store and the drain removal),
`cuda_tiles.zig`, `cuda_startup_test.zig`, `environment_test.zig`.

Fail on T:

| file | hunk | why |
|---|---|---|
| `CHANGELOG.md` | 1 | the anchor at line 41 moved; T's Unreleased block now starts with the #3504/#3503 bullets |
| `zig/src/families/flashnext/cuda_knobs.zig` | both | **the file does not exist at T.** Patch 0004 creates it (`new file mode 100644`, `index 0000000000..d43fb98577`) |
| `zig/src/families/flashnext/cuda_prompt.zig` | the import hunk | adds `const knobs = @import("cuda_knobs.zig")`, so it needs 0004's file; its context also wants `pub const kv_format = @import("cuda_kv.zig");`, a line T no longer has between `const pocket` and `const chunks` |
| `zig/src/platform/environment.zig` | 1 | the rule rows are inserted after `TF_FLASHNEXT_GATHER_EARLY/LOG/LOCK_SCALES`, which only 0004 adds; T has no `TF_FLASHNEXT_GATHER_*` row at all (its neighbours are `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS`, `TF_PROMPT_INTERMEDIATE`, `TENSORFOLD_LFM2_KV_PAGES`, `TF_ROCE_GID_INDEX`) |

Series order does not rescue it. On a pristine T: `0002` applies cleanly; `0001` fails at
`zig/src/platform/environment.zig:50`; `0003` fails at `CHANGELOG.md:30`; `0004` fails at
`zig/src/platform/environment.zig` and `zig/src/platform/environment_test.zig:67`. So the two knobs' home file and
the three GATHER rows its environment hunk leans on cannot be seated either. **The patch's real dependency is 0004,
and 0004 itself needs a restack on T.** That matters for submission: a standalone re-cut must not ship
`cuda_knobs.zig`, which is a 0004 file holding the gather knobs; the two reads belong in `platform/environment.zig`
plus a local read at the call site, as `cuda_chunk.zig:38-42` already does for `TF_FLASHNEXT_READOUT_ROWS`.

### 2.2 Absorbed upstream?

No.

- Drain removal: T still has `if (hooks.logits == .none) try e.complete();` (cuda_prompt.zig:413) and no
  `TF_FLASHNEXT_PROMPT_SYNC`. `git log -S'e.complete()' -- zig/src/families/flashnext/cuda_prompt.zig` returns only
  the file's migration commit `abc43804e`, blame confirms the line, so no upstream commit removed it.
- Chunk default: T has `default_chunk: usize = 1536`; no `3072` chunk default anywhere.
- MXFP8 prompt tile: no `prompt_mx` symbol in `qmmf.cu`; `promptEligible` still requires `.bf16`;
  `git log -S'MXFP8, 128, 128'` is empty. The nearest upstream work is the BF16 tile and its K32 staging, which are
  different kernels.

### 2.3 What it changes at run time

**(a) The drain.** On rank 1 with `hooks.logits == .none`, `Seq.prefill` stops calling `e.complete()` after the chunk
loop, so the next chunk's launches and the request's next step are enqueued before the previous chunk's GPU work
retires; with `TF_FLASHNEXT_PROMPT_SYNC=1`, or with a collective (`world > 1`), the old drain stays. No kernel and no
arithmetic change, **so replies are byte-identical by construction**: the only host memory the GPU reads across a
chunk boundary is the staging queue, and `Pass.chunk` already guards it per pass
(`if (!self.prepared and !self.staged) try s.ready();` at `cuda_batch.zig:507`, with the comment "the gather writes
the scratch's pinned rows, so the last pass's uploads must have read them first", and `s.uploaded()` fencing the host
buffers at `:530`); every other buffer the next chunk writes is written by stream-ordered launches.

**(b) The chunk default.** `default_chunk` 1536 to 3072 changes the rows a pass holds on any server that is not
`one_stream` (`cuda_lanes_load.zig:23`, `cuda_prompt.zig:144`), and the runtime `prompt_rows` each lane admits is the
engine chunk (`cuda_lanes_load.zig:125`, into `cuda_kv_lanes.fits`, `cuda_kv_lanes.zig:90-93`), so on a multi-stream
server every lane's admission rises by 1,536 tokens; `cuda_lanes.zig:34` also makes it the family's compile-time
`prompt_rows` constant. No new launch. **Byte-identical by construction if `splitK`'s documented invariant holds**:
every projection's per-element chain is a function of `(n, k, splitK(n, k))` only, the split's comment says the bits
never depend on the row count, `planSlices` gives `fused` with the same slice order for both 1536 and 3072, and
per-row kernels (attention, norms, MoE) compute each row alone. That invariant is upstream's own written claim, but a
default change still needs the receipt that `CONTRIBUTING.md:79` asks for (KV and final logits at the seams).

**(c) The relaxed MX128 tile.** With `TF_FLASHNEXT_PROMPT_MX128=N` (N > 0, default 0), a prompt pass routes a native
MXFP8 projection of `w.n >= N` to `tf_qmmf_prompt_mx_bf16/f32` through `Lane.matmulPrompt`, a 256-thread, 128 x 128,
3-stage tile with 74496 dynamic bytes; the BF16 projections keep upstream's tile and nothing else changes. It is
**not** byte-identical, and the code says exactly why, in three places:

1. **The accumulation tree changes.** Upstream's exact MXFP8 body (`qmmf_body.cuh:205-240`) sums each K32 block from
   zero (`mma0` for the first K16, `mma` for the second into `d`), then adds it to `acc` with one
   `__fmaf_rn(d, s, acc)`, so there is one rounding point at every 32 inputs. The relaxed body (`prompt_mx_body`,
   patch lines 264-345) carries `acc` through every `mma` and has no per-block reset, so the same products are summed
   in a different fp32 tree. An fp32 sum's value depends on its tree, so the prompt sums differ. The patch's own
   CHANGELOG says it: "a row's sums keep their order whatever the chunk holds, but they are not the exact kernels'
   bits".
2. **The block scale moves into the B fragment.** `fp8pair_unit` multiplies the e4m3 code by a bf16 multiplier built
   as `((byte + 120) << 7)` instead of upstream's `e8m0f(byte)`; for bytes 0 to 134 that multiplier is exactly
   `2^(byte - 127)` (checked by bit arithmetic: byte 0 gives 0x3C00 = 2^-7, times the code's 2^-120 = 2^-127, the same
   as `e8m0f(0) = 0x00400000`; byte 127 gives 0x7B80 = 1.0), so the products are exact and the practical difference
   is item 1.
3. **Two scale bytes go out of range.** `e8m0f` handles the whole byte: 255 is NaN. The relaxed multiplier overflows
   the bf16 exponent field above byte 134: 135 gives 0x7F80 = +inf, 136 to 254 set the sign bit (136 gives 0x8000 =
   -0.0, 255 gives 0xBB80 = -2^-8). A real checkpoint's block scales sit far below 2^7, so this only bites a
   degenerate or adversarial tensor, but it is a divergence from a documented rule and gate 1 (non-finite) would
   catch it on such an input.

**(d) The tile's selection also drops upstream's gates.** `matmulPrompt` checks only `prompt_mx_min_n != 0`,
`w.mode == .mxfp8` and `w.n >= prompt_mx_min_n`. It does not apply `promptEligible`'s `m >= 512`, its `w.k` rule, or
`usesPrompt`'s `2 * promptBlocks(m, w.n) > prompt_sms`, even though the patch comment says "blocks over half the
SMs". A short prompt (say 200 rows) or a narrow projection therefore takes the 128-row tile with a handful of blocks
where the 64-row tile would have four times as many. That is a likely small-prompt regression the measured cells do
not cover.

### 2.4 Upstream-ready?

- **The relaxed tile is not submittable in any form.** `docs/pr/SKILL.md:74` bans "a mode that changes output tokens,
  even opt-in", and the change moves prompt sums, so token equality would have to be proven rather than argued, over
  and above the FP64 reference `CONTRIBUTING.md:84` requires for a changed reduction order. The kernel contract makes
  it concrete: a kernel that replaces another names it and is byte-equal (`docs/pr/SKILL.md` section 4,
  `gates.zig:222-227`), so declaring `.replaces` fails gate 3, and not declaring it would mean the served call site
  changes its output with nothing pinning it.
- **The drain and chunk are submittable, separately**, and neither needs a new setting of its own except the sync
  knob. If the knob is kept it goes through `zig/src/platform/environment.zig` (a `.flag` row, `0 or 1`) and is read
  once at load; that is one new setting for the drain PR and none for the chunk PR. One behaviour a PR splits
  them cleanly: "a prompt pass fills its chunks without draining between them" and "a prompt pass holds 3,072 rows by
  default" are independent lines in different files.
- **Size.** The two re-seated artifacts exist in this directory: `prA-nodrain.patch` is 16 insertions and 1 deletion
  in 5 files (`cuda_chunk.zig` gains `promptSync()`, `cuda_prompt.zig` a `sync_chunks` field, its init store and the
  drain line, plus the `environment.zig` row, its two `environment_test.zig` cases and the CHANGELOG bullet);
  `prB-chunk3072.patch` is 6 insertions and 4 deletions in 4 files (`cuda_batch_state.zig`, `cuda_startup_test.zig`,
  `cuda_batch.zig`'s scratch test, the CHANGELOG bullet). Both sit far under the 600-line file cap. 0005's own
  `qmmf.zig` change leaves that file at 570 lines, so a tile re-cut has about 30 lines of headroom there.
- **Kernel contract.** Neither the drain nor the chunk touches a kernel, so no contract entry. The tile adds two
  kernels and upstream requires, per `docs/kernel-contract.md` and `docs/pr/SKILL.md` section 4, a test type in
  `zig/tests/cuda/contract_*.zig`, the runner list with served shapes and tiles, `registry.zig` records, a planted
  control that the run shows red, the complete `SUMMARY` line and exit status, and the limits audit from
  `tf-cuda-test kernel-contract-limits` over sm_80, 86, 89, 120 and 121. **Our patches carry none of it for 0005**
  (no test type, no record, no control) and **for 0006 only the four records** plus a shared-size unit test.
- **What the existing prompt coverage looks like** (`zig/tests/cuda/contract_qmmf_prompt.zig`), because an exact
  re-cut must copy it: a `Product` with `spec` (accum f32, depth `k/16 + 24`, `ops = 1`, tiles 128 rows, 128 columns
  with `min = 128`, 512 rows with `step = 256`, 2048 for the fused form), `served` shape lists,
  `.replaces = "qmmf BF16 64x64 with identical pinned K slices"` (or the K32 parent), and a planted control that runs
  the same kernel with `w.scale = 1.5`
  (`Product.run`), registered nine times for bf16/fp32 out x plain/fused plus the controls. The records live in
  `zig/src/core/contract/qmmf_prompt_records.zig` with `threads 256`, the dynamic bytes, `opt_in = true` (needed
  because 74496 exceeds the 48 KiB default, `limits.zig:41`), `min_sm = 120`, the nvcc 13.0 register counts and
  `later_pending = true`. 0006's four records follow that pattern exactly (74496 with 175 registers, 49664 with 128).
- **Tests the patches do have.** `environment_test.zig` gains three valid cases, `cuda_startup_test.zig` expects
  3072, `cuda_batch.zig`'s scratch test moves from "< 2 GiB" to "< 5 GiB", and 0006 adds a shared-size test
  (`prompt_mx_shared == 74496`, `prompt_mx2_shared == 49664`). **Missing:** any CUDA test of the new kernels (gates 1
  to 4), any planted control, any test of the new selection gates, and any test that the drain removal leaves the
  staging queue safe (the guard exists in `Pass.chunk`; a host test asserting the drain count would pin it).

### 2.5 Our evidence, quoted

| claim | number | source |
|---|---|---|
| the exact part on its default (tile off) | "cold prompt unchanged with it off; 32k 13.42 s against 14.14 (-5.1%) with `=1024`, replies not yet compared"; the same row says "exact with the tile off" | `patches/1.2.6/README.md:25` |
| the tile, with and without the two-stage form | "g21, PROMPT_MX128=1024 (the relaxed tile, with GEMM2) 3.31 / 13.42, -5.1%"; "g21, PROMPT_MX128=1024, PROMPT_GEMM2=0 3.40 / 13.75, -2.7%" | `docs/CATCHUP-1.2.6.md:504-505` |
| what the tile is worth and what is unproven | "The relaxed MX128 tile is worth 5.1% at 32k, 2.4 points of it from the two-stage GEMM2 form, but it is the inexact tile and its replies have not been compared yet" | `docs/CATCHUP-1.2.6.md:517-518` |
| the exact part's best cells | "Cold prefill (fresh-prompt TTFT): +2.3% C1, +9.5% C2/4/6 on both 64k and 8k (the no-drain + 3072-chunk effect; 2k loses base's c1->c2 step)"; later, tile off against stock: "cold prefill 64k -7.8% at C>=2 / -1.5% C1, 8k -3.3 to -9.5%, 2k -7.0% at C>=2 (parity at C1); decode code +1.2-1.4%, prose +0.5-1.5% (NO trade); golden 15/15 boots identical" | `docs/PARITY-CAMPAIGN-1.2.4.md:184-199, 200-209` |
| the exact part on a careful one-rung sweep | 0005's row is 3.51 / 14.28 against 0004's 3.52 / 14.24 (8k / 32k cold, one stream), and "every other patch is flat"; cell noise about 1% | `patches/1.2.7/README.md` table and bullets |
| the tile's bits | "The tile's own note says its bits are not the exact kernels': it changes prompt sums by design, so this is expected" | `docs/OVERNIGHT-1.2.6.md:100-112` |
| 0006's bits against 0005's tile | "golden 6/6 on all 18 boots, g1 == g0 bit-identical (the same-bits claim verified), cold prefill -3.6% (64k) / -4.2% (32k) vs stock; the two-stage variant vs the 3-stage tile is timing-neutral end-to-end" | `docs/PARITY-CAMPAIGN-1.2.4.md` item 13 |
| 0006's own cell | "32k 13.4 s against 13.8 without it, under MX128" | `patches/1.2.6/README.md:26` |

Two readings of the exact part's value conflict and must be stated as such: the PARITY receipt has -3.3% to -9.5% at
8k and -7.8% at 64k at C>=2 (with the drain and the chunk together), while the 1.2.7 one-rung sweep and the CATCHUP
32k table show it flat at 8k and 32k one-stream (inside stock's own 14.02 to 14.34 spread). The honest position is
that the exact part's gain is real in at least the 64k and multi-stream cells and is not established at 8k/32k
one-stream, so its PR earns its claim on T or reports the negative.

Which cold prompt sizes each piece helps, from those sources:

| cold prompt | exact part (drain + 3072 chunk) | tile on (`MX128=1024`) |
|---|---|---|
| 2k | parity at C1; -7.0% at C>=2 (PARITY) | not measured |
| 8k | -3.3% to -9.5% across the levels in that receipt (PARITY); flat at one stream in the 1.2.7 sweep (3.52 to 3.51) and in CATCHUP (3.49 against stock 3.43) | 3.31 against 3.49, -5.2% (CATCHUP, one stream) |
| 32k | flat in the 1.2.7 sweep (14.24 to 14.28) and in CATCHUP (14.27 against stock 14.02) | 13.42 against 14.14, -5.1%; 2.4 points of it from GEMM2 (CATCHUP) |
| 64k | -7.8% at C>=2 and -1.5% at C1 (PARITY, tile off) | -5.1% against the same receipt's -7.8% with the tile off, so the tile was worse than tile-off there |

**The receipt each vendible PR needs on T.** Upstream's rule is main against the branch, same machine, checkpoint and
settings, alternating arms, a fresh server a run, with both commits named, and token hashes equal on the default path
(`CONTRIBUTING.md:100-120`, and the maintainer's #3368 comment). Concretely:

- the artifacts here are **uncompiled drafts**: `git apply --check` is clean for each on pristine T,
  `zig fmt --check` exits 0 on every edited Zig file (so they parse), `git diff --check` is clean, and the code paths
  apply in either order (A then B and B then A with `--exclude=CHANGELOG.md`); both patches add their bullet at the
  same Unreleased anchor, so applying both together needs the ordinary CHANGELOG resolution, which is also what the
  ATC overlap check will report. The first build is the laptop cross-compile in `AGENTS.md`'s gotcha list
  (`zig build compile-config-server -Dtarget=aarch64-linux-gnu`), which this campaign's rules forbid here, so it is
  the first step before any box build.

- both PRs: `tools/bench_openai.py` decode at 1, 2, 4, 6 and 8 streams (512-token prose and code, greedy, 2 to 3
  reps), and `tools/bench_cache.py --require-cold` with `--prompt-cache-gib 0` at 2k, 8k, 32k and 64k, main against
  branch, alternating, a fresh boot a cell (2 arms x 5 stream cells + 2 arms x 4 cold cells = 18 boots), plus
  `tools/bench_concurrent.py --levels 1,4 --alone --serial` and the four exactness contracts (drafted equals plain,
  resumed equals fresh, concurrent equals solo, cancel and reset leave the next request valid) on 2 boots, plus
  token hashes on every cold cell. That is **one GPU window, about 20 fresh boots, 2 to 3 hours on spark6**.
- the chunk PR additionally states the memory side: scratch at the default chunk (the patch's own test is "< 5 GiB",
  the base "< 2 GiB"), the pool and `prompt_rows` admission at 2, 6 and 8 streams, and a 2k cell where it changes
  nothing (one pass on a one-stream server).
- the exact tile, if it is built: the same 20-boot window, plus the CUDA contract build and run
  (`zig build kernel-contract -Dnvcc=...`, then `zig build fatbins kernel-contract-fatbins -Dsm=80,86,89,120,121`
  and `tf-cuda-test kernel-contract-limits`), plus `zig build test test-golden`, `zig fmt --check`, `git diff
  --check` and `tools/pr_check.py`. **Two GPU windows** (one for the A/B, one for the contract build and run).
- the drain PR must also be measured alone, with `default_chunk` left at 1536, because every existing number for it
  was taken with the chunk change alongside.

### 2.6 Verdict and the split

**SPLIT.**

**PR-A (SUBMIT candidate, rank 1).** Title: "Flash Next on CUDA: a prompt pass fills its chunks without draining the
stream between them". Branch `flashnext-prompt-nodrain-up` on `BadAd84/TensorFold`, cut from T, with
`prA-nodrain.patch` (this directory) as the content. It puts `TF_FLASHNEXT_PROMPT_SYNC` (default 0) in
`platform/environment.zig`, reads it once in `Engine.initRank` through `cuda_chunk.zig`'s `promptSync()` (not 0004's
`cuda_knobs.zig`), stores it on the Engine, and keeps the drain for `world > 1`. `git apply --check` is clean on T and
`zig fmt --check` passes.

**PR-B (SUBMIT candidate, rank 2).** Title: "Flash Next on CUDA: a prompt pass holds 3,072 rows". Branch
`flashnext-prompt-chunk3072-up`, cut from T, with `prB-chunk3072.patch` (this directory) as the content:
`default_chunk` 1536 to 3072, the startup expectation, the scratch test renamed and re-bounded from 2 GiB to 5 GiB
(the exact figure comes from the tree's own test on the box; do not replace it with a guess), one CHANGELOG bullet.
Independent of PR-A in the code (either order applies); both add their bullet at the same Unreleased anchor, the
ordinary CHANGELOG case.

**RETIRE the relaxed tile** (`prompt_mx_body`, `fp8pair_unit`, the two `TF_PROMPT_MX` instances, `Lane.matmulPrompt`,
`qmmf.prompt_mx_min_n`, `TF_FLASHNEXT_PROMPT_MX128`) as an upstream candidate. It stays a downstream-only lever if the
owner wants it; our served recipe already forces its default to 0 (`scripts/qwen38/zig/target/overlay.py`, the repair marked
"knobs: the relaxed MX128 tile off by default again").

**HOLD the exact re-cut** (section 4) until it is built and measured.

## 3. Patch 0006 (`patches/main-964174ea05/0006-prompt-gemm2.patch`)

67 insertions, 8 files: `qmmf.cu` +7/-4, `qmmf_prompt_records.zig` +34/-2, `qmmf.zig` +23/-3, `cuda_knobs.zig` +5,
`cuda_prompt.zig` +1, `environment.zig` +1, `environment_test.zig` +1, `CHANGELOG.md` +2.

### 3.1 Applies on T?

No. 16 hunks in 8 files: **5 apply on T but are orphaned, 11 fail.**

The five that apply are the four `qmmf_prompt_records.zig` hunks and the shared-size test appended at the end of
`qmmf.zig`; they apply because they anchor on lines that exist on T, but they describe kernels that would not exist
(records for `tf_qmmf_prompt_mx2_*`, and a test asserting `prompt_mx_shared`/`prompt_mx2_shared`). The eleven that
carry the change fail because their context is 0005's new text: `qmmf.cu`'s `TF_PROMPT_MX` macro signature and
instances, `qmmf.zig`'s `prompt_mx` constants/field/load/launch, `cuda_knobs.zig` (absent, 0004's file),
`cuda_prompt.zig`'s `mx2_tile` store, the `environment.zig` row after 0005's, and the `environment_test.zig` case
after 0005's. **0006 has no independent application at all**: it is a delta on 0005's tile.

### 3.2 Absorbed upstream?

No: no `prompt_mx2` symbol, no `TF_FLASHNEXT_PROMPT_GEMM2`, no `mx2_tile`. But the *idea* is upstream's: the BF16
K32 staging already runs `__launch_bounds__(256, 2)` at 49152 bytes, two blocks an SM, exact (#1848). So nothing about
"two blocks an SM" is new; the only new thing is applying it to the MXFP8 tile.

### 3.3 What it changes at run time

With `TF_FLASHNEXT_PROMPT_GEMM2=1` (the serve recipe exports it, `AGENTS.md`'s note on `config.sh`, and it acts only
when `PROMPT_MX128` is also set, which the recipe forces to 0), `Lane.matmulPrompt` launches
`tf_qmmf_prompt_mx2_bf16/f32` instead of `prompt_mx`: `STAGES` 3 to
2, `__launch_bounds__(256, 2)`, dynamic shared 74496 to 49664, so two blocks fit an SM (2 x 49664 = 99328, under
sm_120/121's 99 KiB opt-in limit at `limits.zig:50-51`). **Its bits equal 0005's tile bit for bit, and that is exact
by construction**: the only differences are the pipeline depth and the occupancy bound, the K-group order and every
`mma`/accumulation are unchanged, and nvcc cannot reorder `asm` accumulator chains. Our own receipt says the same
("g1 == g0 bit-identical", `docs/PARITY-CAMPAIGN-1.2.4.md` item 13). It therefore inherits 0005's non-exactness
against upstream's kernels and nothing else; the change is exact relative to the kernel it replaces.

### 3.4 Upstream-ready?

- **Not submittable**, because the kernel it restructures is the relaxed one, and it would ship only alongside that
  tile. On its own it changes nothing.
- If the exact re-cut exists (section 4), the occupancy idea could be re-offered on top of it, but it is not free:
  upstream's shared-size formula floors a non-cluster tile at `PARTIALS = MT * NT * 4 * THREADS * 4 = 65536`
  (`qmmf.cu:47-49`), so a two-stage exact tile at 2 x 24832 = 49664 would still *declare* 65536 and lose the second
  block. 0006 avoids this only because its body is bespoke and never uses `Tile::SMEM`. A re-cut would need its own
  shared-size structure (the K32 staging shows the pattern) or a change to `Tile::SMEM` gated on `CLUSTER`, and the
  latter touches every registered instance's dynamic bytes.
- **Our evidence is split**: 2.4 points at 32k in the CATCHUP sweep (13.75 to 13.42), and "timing-neutral end-to-end"
  in the PARITY receipt (item 13). Both are in our docs; the sweep's own spread covers the smaller figure. The prize
  is small and unproven.
- **Contract**: 0006 carries the four records (which is the cheapest part) and no test type, no control, no
  `SUMMARY`. Same gap as 0005, and the records' register counts (175 and 128) are nvcc 13.0 measurements taken on the
  box, not re-derivable on this laptop.

### 3.5 Verdict

**RETIRE** 0006 from the upstream list, together with the relaxed tile it belongs to. **HOLD** the idea (a
two-stage, two-blocks-an-SM form of an *exact* MXFP8 tile) behind the section 4 re-cut and its measurement; if the
exact tile is worth less than about 2 points, the occupancy variant is not worth its own PR plus contract cost.

## 4. The only MXFP8 128-row tile worth offering: an exact re-cut (HOLD)

The tile geometry is not what loses exactness; the accumulation is. Upstream's MXFP8 body needs two changes for a
128-row tile, and neither touches the arithmetic:

1. **The scale load must take two 64-column tiles.** The general loader (`qmmf_body.cuh:93-101`) already walks
   `BN / 64` weight tiles, but its scale loop (lines 98-101) copies `T::S` bytes from `(n0/64)*KG*S`, i.e. two K groups
   of tile 0 for `BN = 128`, because `packScales` stores `[64-column tile][K group][64][2]`
   (`zig/src/cuda/mxfp8.zig:11-19`). The relaxed body already loads per tile (`bs + ((n0/64 + t)*KG + g)*PER`); the
   exact body needs the same loop.
2. **The static assert must admit it.** `qmmf_body.cuh:11` allows `BN == 128` only for BF16; add `MODE == MXFP8`.

Then the existing arithmetic runs unchanged: `mma0`/`mma` over K16, a per-K32 `d`, one `__fmaf_rn(d, s, acc)`, the
same output mapping. The per-element chain does not depend on `BM` or `BN` (MT and NT only decide which warp computes
which tile), so the 128-row instance computes the same bytes as the 64x64 instance it would replace, for both the
plain and the fused slice plans (the slice sum order is the same, so `reduce_kernel` and the fused `tot` agree). That
is the `.replaces` claim gate 3 can enforce byte for byte (`gates.zig:222-227`).

What it costs, and why the outcome is genuinely uncertain:

- **Registers.** The exact form needs `acc` plus `d`, 64 floats each at MT = NT = 4, so about 128 registers of
  accumulators a thread before `wq`, `sq` and addresses. The relaxed body measures 175 registers in total; the exact
  form would land near 240 at 256 threads (an estimate: the exact 64-row tile measures 168 at 128 threads and the
  relaxed body 175, and the extra `d` is 64 floats), which fits under the 255 cap but leaves one block an SM at 74496
  shared. That is exactly the BF16 tile's shape (95 to 255 registers, 98432 bytes), so it is plausible, but a spill
  would eat the gain.
- **Shared size.** At three stages it is 74496, the same as the relaxed tile, so `prompt_mx_shared` carries over. At
  two stages the `PARTIALS` floor blocks the second block (section 3.4).
- **Selection.** Extend `promptEligible`/`usesPrompt` rather than adding a parallel selector, so the `m >= 512` floor,
  the `w.k` rule and the `2 * promptBlocks > prompt_sms` fill gate apply. That also removes the small-prompt hazard in
  section 2.3(d). A switch follows #1846's pattern (a `.flag` row, default on only with a receipt), and its name
  should cover both formats if it replaces `TF_FLASHNEXT_PROMPT_BF16`.
- **Size.** About 8 lines in `qmmf_body.cuh`, two instantiations in `qmmf.cu` (about 10 lines), roughly 30 lines in
  `qmmf.zig` (constants, `loadPrompt`, the launcher, eligibility), 2 to 4 records, one contract test type plus a
  product and a control (about 120 lines), one CHANGELOG bullet. `qmmf.zig` is at 537 lines on T and has about 30
  lines of headroom under the 600-line cap, so the launcher may need its own file.
- **The prize.** The relaxed three-stage tile measured about 2.7 points at 32k once GEMM2's 2.4 points are removed
  (CATCHUP: 14.14 to 13.75 with GEMM2 off), and GEMM2 itself is disputed (2.4 points in one doc, neutral in another).
  The exact tile keeps the per-block `fma` that the relaxed one dropped, so its share is at most those 2.7 points and
  could be zero. Measure before writing any PR text.

Proposed branch name if it is built: `flashnext-prompt-mx128-exact-up`. It is new work, not a re-seat of 0005; it
shares only the geometry and the loader shape with the retired tile.

## 5. Rank by expected gain on the owner's workload (decode at 2 to 8 streams and cold prompts on one GB10)

1. **PR-A, the drain removal.** Exact, 16 insertions in 5 files, and its best cells are the owner's own case: a cold 64k prompt
   arriving beside decoders (-7.8% at C>=2, -1.5% at C1) with a small decode gain in the same receipt. It is flat in
   two other sweeps, so its PR must earn the number on T; the upside is the largest of the exact pieces and the risk
   is a negative result, not a bad change.
2. **PR-B, the 3,072-row chunk.** Exact if the split invariant holds, 6 insertions in 4 files, bundled with PR-A in every existing
   measurement and never measured alone. Its costs (a scratch bound that moves from under 2 GiB to under 5 GiB, 1,536
   more rows in every lane's admission, longer prompt passes in front of decoders) are real, so it goes second and
   needs its own no-slower table at 2 to 8 streams.
3. **The exact MXFP8 128-row tile (HOLD).** Potentially the biggest single cold-prompt cell (the relaxed form's 5.1%
   at 32k and 5.2% at 8k), but the exact form's arithmetic is slower than the relaxed form's by one fp32 `fma` a
   K32 block and its register pressure is close to the cap, so the expected gain is unknown and possibly zero. It also
   costs a contract test, a control and a second GPU window.
4. **0006's two-stage form (RETIRE).** Zero to 2.4 points, disputed between two of our own docs, and it needs the
   `PARTIALS` workaround to keep two blocks with an exact body.

## 6. Commands and their decisive output

    # upstream tip
    timeout 90 git -C work/upmain fetch origin main
    git -C work/upmain log -1 --format='%H %ci %s' origin/main
    -> 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7 2026-11-16 15:26:10 +0000 changelog: #3572 under Unreleased

    # pristine worktrees at T
    git -C work/upmain worktree add --detach ../Triage-prompt 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7
    git -C work/upmain worktree add --detach ../Triage-prompt-b 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7

    # per-hunk check of 0005 on T (18 hunks, LF patches, one hunk a file)
    git apply --check -v ../../patches/main-964174ea05/0005-prompt-chunk.patch
    -> error: patch failed: CHANGELOG.md:41
    -> error: zig/src/families/flashnext/cuda_knobs.zig: No such file or directory
    -> error: patch failed: zig/src/families/flashnext/cuda_prompt.zig:11
    -> error: patch failed: zig/src/platform/environment.zig:59
    -> every other file: "Checking patch ..." with no error (and "Hunk #1 succeeded at 130 (offset -1 lines)",
       "Hunk #1 succeeded at 53 (offset -1 lines)", "Hunk #1 succeeded at 125 (offset -1 lines)")

    # per-hunk check, isolated, so a failure in one file cannot hide another
    for f in work/upsubmit/Triage/.hunks/*.patch; do git apply --check "$f"; done
    -> OK qmmf.cu.0, qmmf.zig.0-3, cuda_batch.zig.0-1, cuda_batch_state.zig.0, cuda_prompt.zig.1-2, cuda_tiles.zig.0,
       cuda_startup_test.zig.0, environment_test.zig.0
    -> FAIL CHANGELOG.md.0, cuda_knobs.zig.0-1, cuda_prompt.zig.0, environment.zig.0

    # series order on T
    for p in 0001-rows 0002-copy-resync 0003-kv8 0004-ngram-row-cache; do git apply ../../patches/main-964174ea05/$p.patch; done
    -> 0001: error: patch failed: zig/src/platform/environment.zig:50
    -> 0002: (clean)
    -> 0003: error: patch failed: CHANGELOG.md:30
    -> 0004: error: zig/src/platform/environment.zig: patch does not apply; error: patch failed:
       zig/src/platform/environment_test.zig:67

    # 0006 per hunk on T
    for f in work/upsubmit/Triage/.hunks6/*.patch; do git apply --check "$f"; done
    -> OK qmmf_prompt_records.zig.0-3 and qmmf.zig.4 (orphaned data and a test), FAIL the other 11 (qmmf.cu.0-1,
       qmmf.zig.0-3, cuda_knobs.zig.0, cuda_prompt.zig.0, environment.zig.0, environment_test.zig.0, CHANGELOG.md.0)

    # upstream's rule text at T
    grep -rn "lossy\|output tokens\|even opt-in" AGENTS.md CONTRIBUTING.md README.md docs/pr/SKILL.md docs/atc/SKILL.md
    -> docs/pr/SKILL.md:74: "TensorFold takes no lossy weight or cache formats, even opt-in, and no mode that changes
       output tokens, even opt-in. Output must stay token-equal to the serial reference."
    -> CONTRIBUTING.md:114: "... with token hashes equal on the default path. An opt-in that changes tokens says so
       and shows its proof."

    # the contract gate a replacement kernel must pass
    sed -n '210,250p' zig/src/core/contract/gates.zig
    -> if (k.spec.replaces) |what| { ... if (!std.mem.eql(u8, out, want)) return say(.fail, .shapes, name,
       "at {d}x{d}x{d} its bytes differ from {s}'s from byte {d}", ...); }
    -> const how = if (k.spec.replaces != null) "bit-equal to the kernel it replaces" else ...

    # the scale bytes, checked by bit arithmetic (python, no GPU)
    -> e8m0f(0) = 0x00400000 = 2^-127; e8m0f(1) = 0x00800000 = 2^-126; e8m0f(255) = 0x7FC00000 = NaN
    -> relaxed unit: byte 0 -> 0x3C00 = 2^-7 (times the code's 2^-120 = 2^-127, the same), byte 127 -> 0x7B80 = 1.0,
       byte 135 -> 0x7F80 = +inf, byte 136 -> 0x8000 = -0.0, byte 255 -> 0xBB80 = -2^-8

    # the maintainer's constraints (read-only)
    gh api repos/ashhart/TensorFold/issues/3368/comments --jq '.[] | .body'
    -> "Default path exact. Every checkpoint served today keeps its tokens: same sums, same order."
    -> "Kernels go in the kernel contract with a float64 reference of the stored weights, a planted control that the
       contract must catch, and the CUDA SUMMARY line."
    -> "Receipts on current main from your GB10: main against the branch, alternating arms, a fresh server each run,
       with both commits named."

    # the BF16 tile and its K32 staging at T
    grep -n "prompt" zig/kernels/cuda/qmmf.cu | head
    -> 202-210: BF16_PROMPT(false,false), (false,true), (true,false), (true,true) at 128x128, 2 warps x 4 warps, 3 stages
    -> 214-245: PromptK32Tile with static_assert(SMEM == 49152) and __launch_bounds__(256, 2)

    # MXFP8 is excluded from the prompt tile at T
    sed -n '174,178p' zig/src/cuda/qmmf.zig
    -> pub fn promptEligible(m: usize, w: Weight) bool { return m >= prompt_rows and w.mode == .bf16 and w.n >= 128
       and (w.k >= 512 or (w.n == 10240 and w.k == 320)) and w.npad % 128 == 0; }


    # the two candidate patches, built here and proven on a pristine T
    git -C work/upmain worktree add --detach ../Triage-pA 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7
    git -C work/upmain worktree add --detach ../Triage-pB 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7
    <edit PR-A files> ; git -C work/Triage-pA diff --check ; git -C work/Triage-pA diff > prA-nodrain.patch
    <edit PR-B files> ; git -C work/Triage-pB diff --check ; git -C work/Triage-pB diff > prB-chunk3072.patch
    -> prA-nodrain.patch: 5 files, 16 insertions, 1 deletion
    -> prB-chunk3072.patch: 4 files, 6 insertions, 4 deletions

    C:/Users/Adam/tools/zig-x86_64-windows-0.17.0/zig.exe fmt --check <every edited .zig>   # parse, not a build
    -> rc 0 for A's four files and B's three

    git apply --check prA-nodrain.patch   -> clean
    git apply --check prB-chunk3072.patch -> clean
    git apply prA-nodrain.patch prB-chunk3072.patch
    -> error: patch failed: CHANGELOG.md:4 (both bullets at the same Unreleased anchor, the ordinary case)
    git apply --exclude=CHANGELOG.md prA-nodrain.patch prB-chunk3072.patch   -> applied
    git apply -R --exclude=CHANGELOG.md ... ; git apply --exclude=CHANGELOG.md prB ... prA ...   -> applied
    -> the code paths are order-independent; only CHANGELOG.md needs a merge

    # cleanup: every scratch worktree was removed and pruned (no junctions in any of them)
