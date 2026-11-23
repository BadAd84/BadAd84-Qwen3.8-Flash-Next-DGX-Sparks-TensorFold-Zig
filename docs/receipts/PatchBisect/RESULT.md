# SHARED_DIRECT: the r2 series' answer defect, what turning it off costs, and the code mechanism


**Run record.** The ticket's patch-prefix ladder was stopped by the Main agent before any prefix was built: its one
window (03:41:50 to 03:46:47Z) took only the two image controls (reported in section 1) and then aborted on a
build-context path error in the driver, not on a measurement. The cost window was then run in two attempts: the
first (03:51:25 to 03:58:40Z) took the three confirmation arms and aborted at the first decode cell because the
decode harness was not given `API_URL` and tried production's `:8888`; the second (04:00:14 to 04:26:16Z) reused the
same three confirmation boots (same image, same env, re-gated) and completed decode, TTFT and the resume probe. All
three attempts' logs are in the fetched evidence.

## 1. Confirmation: the shared-direct flag alone decides the answers

One GPU lock hold on spark6, one image (`tensorfold-qwen38:s2-1ece6e6d`,
`sha256:fe5a33931b63506103eb08d8d2e8b244efadc65b8fae028255235fc22781f044`), the recipe's own serving shape
(4 streams, 131072-token window, bf16 KV, drafts on, thinking off) and the recipe's own environment, read back from
`docker inspect` on every boot and diffed against `in/ref-env.txt` with the arm's one-line delta applied. Each arm
boots, answers the same 20 GSM8K items (1,330 to 1,494 prompt tokens, the recorded request bodies), and is compared
with the 2026-11-19 reference (`in/ref20.json`, the QCMPB text hashes) by exact text-hash equality.

| arm | delta | verdict | eqB (equal to the reference) | eqI4WB (equal to Int4Window arm B) | `####` | gold | boot |
|---|---|---|---:|---:|---:|---:|---:|
| CF0A | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` | RESTORES | 20/20 | 0/20 | 20 | 20 | 55 s |
| CF1 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` | BROKEN | 0/20 | 20/20 | 3 | 1 | 56 s |
| CF0B | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` | RESTORES | 20/20 | 0/20 | 20 | 20 | 58 s |

- **20/20 with the flag off, twice.** Two separate boots of the same binary with the same one-line environment change
  return the reference replies exactly, all 20 text hashes and all 20 markers and gold answers.
- **0/20 with the flag on, and it is the finding's own text.** The `=1` arm reproduces the Int4Window arm B replies
  byte for byte (eqI4WB 20/20): 3 of 20 replies carry `####`, 1 carries the right gold answer.
- The reference is valid in this campaign: the stopped ladder window's control boots on the same items and bodies
  measured `m-1ece6e6db` (main at the series' base) RESTORES 20/20 and `s2-1ece6e6d` BROKEN 0/20 with eqI4WB 20/20
  (that window's `out/K0` and `out/K20`, 2026-11-22T03:43-03:44Z; the image ids are gated to `323872ff...` and
  `fe5a3393...`).
- Independently, the PromptFid window's second run measured the same single lever on the same image before this
  window (its `out/ARMS`: `T-SHAREDDIRECT0 RESTORES eqB=20` followed by `CONF1` and `CONF2` RESTORES, every other
  toggle BROKEN).
- The environment gate is what makes the two arms comparable: `env-diff.txt` is empty in all three arms, so the
  container carried exactly `ref-env.txt` plus the named flag value, and the image id gate held on every boot.

## 2. What turning it off costs

All arms below are the same image and serve shape as section 1, with one variable changed and the container
environment read back and diffed (gate empty) on every boot. Decode and TTFT arms are two fresh boots an arm,
alternated (D0-1, D1-1, D0-2, D1-2 and T0-1, T1-1, T0-2, T1-2); the cells are the earlier windows' harnesses run
unchanged (`tfm_decode.py` for decode, `ttft.py` for cold TTFT).

### 2.1 Decode is flat within noise

`tfm_decode.py` with 2 passes of prose and code, 512 greedy tokens a request. Aggregate is the sum of the per-stream
decode rates (one pass's figure); the table shows the mean over the two passes of each of the two boots.

| cell | `=0` agg tok/s | `=1` agg tok/s | `=0` against `=1` |
|---|---:|---:|---:|
| C1 prose | 63.59 | 63.33 | +0.4% |
| C1 code | 82.21 | 81.59 | +0.8% |
| C8 prose | 229.57 | 228.92 | +0.3% |
| C8 code | 335.67 | 333.72 | +0.6% |

The four per-pass aggregates an arm: C1 prose `=0` 61.36, 66.34, 61.08, 65.60 and `=1` 61.05, 65.50, 61.06, 65.72;
C8 code `=0` 338.12, 333.44, 337.84, 333.28 and `=1` 338.60, 331.60, 333.69, 330.99. The spread inside an arm is
larger than the gap between arms.

The draft counters are identical between the arms in every cell (C1 prose 578 drafted / 365 accepted, pass 0; 536 /
379, pass 1; C1 code 639 / 422 and 625 / 426; C8 prose 3,665..3,672 / 2,352..2,354 and 3,648..3,656 / 2,403). That is
what the mechanism predicts: these cells' prompts are the harness's short prompts (the sub-512-row class where both
routes run the same 64-row arithmetic), so their hidden states are identical, and a decode pass never sets
`shared_direct` anyway. The fix costs nothing in decode.

### 2.2 Cold TTFT carries the whole cost

`ttft.py` with `--sizes 8k,32k --thinking off --loads idle --warm-add 0 --reps 3`; medians of three cold samples a
boot, two boots an arm.

| case | `=0` median (s), per boot | `=0` mean | `=1` median (s), per boot | `=1` mean | `=0` against `=1` |
|---|---|---:|---|---:|---:|
| cold8k-off idle | 3.723, 3.713 | 3.718 | 3.519, 3.572 | 3.546 | **+4.9%** |
| cold32k-off idle | 14.907, 14.997 | 14.952 | 14.238, 14.362 | 14.300 | **+4.6%** |

The split puts all of it in the engine's own prefill: 8k `=0` prefill 3.713 s against `=1` 3.538 s; 32k 14.939
against 14.277. Admit is 0.007 to 0.022 s, and every sample reported `excluded 0` (all cold). So turning the lever
off costs about 0.17 s at 8k and 0.65 s at 32k of cold prefill, a 4.6 to 4.9% TTFT change at this shape: that is the
price of the fix.

### 2.3 The resume probe on `=0`: cold and cold-then-cached agree

`resume_bench.py --tokens 8606 --reply 16` on the `=0` boot, drafted path on: the cold run of the filler prompt, its
first cached resume, and a third run after ten more fresh fillers. The harness's `--tokens` is a target for its
generator; the request actually carried 8,217 prompt tokens (recorded in the rows).

| run | prompt tokens | cached tokens | ttft (s) | reply token_sha256 |
|---|---:|---:|---:|---|
| A1 cold | 8,217 | 2 | 3.922 | `e617f368366668eedd5ba171311645a0374ea9bc1a86474e8dc51812ecaff998` |
| A2 first resume | 8,217 | 8,210 | 0.105 | `e617f368366668eedd5ba171311645a0374ea9bc1a86474e8dc51812ecaff998` |
| A3 after 10 fresh fillers | 8,217 | 8,210 | 0.071 | `e617f368366668eedd5ba171311645a0374ea9bc1a86474e8dc51812ecaff998` |

All three replies are token-identical. **With shared-direct off, the cold reply and the cached resumes agree**, and
the cached TTFT is 0.10 s against the cold 3.92 s, so the prefix was genuinely served from the cache. RowInv's
finding (cold versus cached replies differ on the r2 image, with the draft stream differing between the two states)
was this defect: the broken prefill changed the state the MTP head drafts from. One caveat: this is one boot of this
harness's generator at 8,217 actual tokens with drafting on, not a re-run of RowInv's fixed 8,606-token probe or its
non-drafted arm.

### 2.4 The balance

Turning `TF_FLASHNEXT_PROMPT_SHARED_DIRECT` off: decode unchanged within cell noise, cold TTFT 4.6 to 4.9% higher at
8k and 32k, and the cached-resume reply divergence gone. The lever's measured value is that ~5% cold prefill at these
sizes; its cost was the 20/20 answer set.

## 3. The mechanism, from the applied r2 tree

The tree quoted here is `1ece6e6db` plus `patches/main-1ece6e6db-r2` 0001-0020; it is the tree the image was built
from (`stage_base` in the driver proved it file by file against `s2-series.manifest`: 12,621 entries, 0 mismatches).
Paths are relative to that tree's root.

**3.1 Why our arms take the path: the recipe opts in, the code defaults out.**

- `zig/src/families/flashnext/cuda_knobs.zig:65-67`:
  ```zig
  /// TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1: the MoE write-back reads the shared expert fp32 output in place.
  pub fn sharedDirect() sys.environment.Error!bool {
      return sys.environment.read(bool, "TF_FLASHNEXT_PROMPT_SHARED_DIRECT", false);
  }
  ```
- The recipe turns it on: `~/work/lanes/rpr/recipe/scripts/config.sh:131`
  `export TF_FLASHNEXT_PROMPT_SHARED_DIRECT="${TF_FLASHNEXT_PROMPT_SHARED_DIRECT:-1}"`.
- Patch 0008 adds that variable, its reader, both call sites, the kernel and the environment rule (grep: no patch
  0001-0007 names it). Main at the series' base therefore has nothing to read it: the `m-1ece6e6db` image ignored the
  recipe's export and ran the non-direct route. The r2 image is the first to consume it, which is why the reference
  and the series differ with identical code around them.

**3.2 The gate: every prompt pass takes it, no decode pass does.**

`zig/src/families/flashnext/cuda_batch_hc.zig:45-47`:
```zig
pub fn moeRunPromptAware(pass: anytype, native: anytype, n: usize, pairs: usize, plan: anytype, keep: anytype) !void {
    if (pass.hooks.prompt and (knobs.sharedDirect() catch false) and (pass.hooks.logits == .none or pass.hooks.streams != 0) and
        pass.hooks.moe_add == null and pass.m.pocket == null and keep.moe_branch == 0 and native.world == 1) pass.shared_direct = true;
```
The condition is prefill (`hooks.prompt`) versus decode, not prompt length. The length enters in 3.4.

**3.3 What the flag changes: which kernel computes the shared expert's down projection.**

`zig/src/families/flashnext/cuda_batch_side.zig:48-57`:
```zig
pub fn down(pass: anytype, st: cuda.Stream, input: u64, native: anytype, n: usize) !void {
    const s = pass.s;
    const w = native.shared[2].native.?;
    if (!pass.shared_direct and w.n == dims and cuda.qmmf_shared.eligible(pass.k.native_lane, n, w, moe_w, slots * dims))
        return pass.k.native_lane.matmulF32Strided(st, input, moe_w, n, w, s.y + (slots - 1) * dims * 4, slots * dims);
    const glue = pass.tri.own orelse return error.NativeGlueRequired;
    try pass.k.nativeMatmul(st, input, moe_w, n, w, s.shared_out, s.native_part, .f32);
    // with the write-back reading it in place, the rows stay in shared_out and y's slot keeps its zeros
    if (pass.shared_direct) return;
    try glue.sharedScatter(st, s.shared_out, s.y, n, dims, slots);
```
With the flag clear, the first branch takes `qmmf_shared.matmulF32Strided` (the 64-row shared-down kernel) and writes
the fp32 row straight into y's reserved MoE slot. With the flag set, that branch is skipped, the down runs through
`nativeMatmul` into `s.shared_out`, and the function returns before the scatter copy.

**3.4 The in-place read is exact; the divergence is made one step earlier.**

The write-back is deferred one layer: the layer loop sets `self.pending = layer;` (`cuda_batch.zig:573`), and the next
layer dispatches it (`cuda_batch.zig:187`:
`if (self.shared_direct) return hc.writebackSharedDirect(self, r0, n);`). `cuda_batch_hc.zig:33-41` launches mode 3
with `s.shared_out + r0 * dims * 4`, and `zig/kernels/cuda/flashnext_hc.cu:81-83` sums
`BR[(long long)r * D + d]` where mode 2 sums `Y[((long long)r * SLOTS + TOPK) * D + d]`. The copy it replaces is a
plain element copy (`fn_shared_scatter`, same file 523-526:
`Y[(r * SLOTS + SLOTS - 1) * D + j] = SHARED[r * D + j];`), so the in-place read sees exactly the value the copy
would have placed in the slot. Nothing is misread.

The change is the kernel behind `s.shared_out`. `nativeMatmul` is `qmmf.matmulOut`; for a BF16 weight it sets
`const prompt = l.usesPrompt(m, w)` and `bm = 128` when prompt, else the bucket tile (`zig/src/cuda/qmmf.zig:341-350`).
`usesPrompt` requires `promptEligible` (`qmmf.zig:187-190`), whose first term is `m >= prompt_rows` with
`prompt_rows = 512` (`qmmf.zig:170`). At the shared down's shape (n=2,560, k=640) the block count at 1,330-1,494 rows
is `2 * ceil(m/128) * ceil(2560/128) = 440..480`, above `prompt_sms` (the device's SM count, 48 in the host test's
lane), so the 128-row prompt tile runs.

The strided route was eligible on the reference for this weight: `qmmf_shared.eligible` (`qmmf_shared.zig:8-11`)
requires BF16 and `planFor(...).sk == 1`, and with `group = 64` (`qmmf.zig:15`) `splitK(2560, 640)` leaves `sk = 1`
(`tiles * 1 = 40 < 192`, but `groups / (sk * 2) = 10 / 2 = 5 < 8` stops the loop at 1). The reference arm is the one
that measured the toggle restoring, which is only possible if the first branch was taken; the code and the
measurement agree.

**Why a 43-58 token prompt is unaffected and a 1,330-token prompt is not.** Below 512 rows `promptEligible` is false,
`usesPrompt` is false, and `matmulOut` runs the same 64-row bucket tile that the strided launcher mirrors (its host
test, `shared down stride: geometry, output address and stride match the contiguous launcher`, pins the geometry,
destination address and stride). Same arithmetic, same bits: the direct route is output-identical there. At 512 rows
and above the direct route swaps in the 128-row prompt tile, which the reference never ran for this projection. The
shared expert's fp32 row therefore differs, and the deferred write-back adds that different value into every token's
MoE branch from the first layer; greedy decoding diverges from the first changed token. The defect is a kernel
substitution at a row threshold, not a buffer overrun and not a stale read.

**3.5 The other half of 0008 is not this defect.** `TF_FLASHNEXT_HEAD_PIECE=256` was booted on the full series in the
PromptFid window and stayed BROKEN with the same wrong answers (eqB 0, eqI4WB 20); the shared-direct flag alone
restores 20/20 there and here.

**3.6 The class.** A default-on environment lever whose code path changes *which kernel fills a buffer*, with the
switch keyed on a row or column threshold. This family already has three such thresholds (`prompt_rows = 512`,
`fused_rows = 1024`, `TF_FLASHNEXT_PROMPT_MX128`'s `mx128MinN`), and a toggle tried at one prompt length cannot see a
threshold. Any lever of this shape needs a bit-for-bit check against the reference on both sides of its threshold
before it is called a same-bits optimisation. In this series only 0008 touches `cuda_batch_side.zig` or the mode-3
kernel; the neighbouring prompt and read-out code in the same files is edited by 0009 and 0018
(`cuda_batch_hc.zig`) and the prompt-tile selection by 0005, 0006, 0017 and 0018 (`qmmf.zig`), which is why the rule
is stated for the class and not for 0008 alone. Not claimed here: that any other lever of this shape is broken.

## 4. What this does not prove

- One checkpoint (`nvidia/Qwen3.8-Flash-Next-FP4-Local`), one image (the r2 series), one device (spark6), one prompt
  set (20 items of 1,330-1,494 tokens). The exact-text oracle is the 2026-11-19 FP4 run's reply hashes.
- The 512-row threshold is derived from the code (`prompt_rows`, `promptEligible`, `splitK` at the shared down's
  shape), not swept: no short-prompt run was made in this window. The claim that prompts below 512 rows are unaffected
  therefore rests on the code identity above, consistent with the short-prompt behaviour reported elsewhere.
- The cost cells are two fresh boots an arm, alternated, on one serve shape; they price the two arm states, not a
  controlled kernel microbenchmark. Decode passes never set `shared_direct`, so any decode difference is a
  consequence of the different prefill state (draft acceptance), not of decode-time work.
- The resume probe is one boot and one sequence on `=0`; it uses the server's `token_sha256` for cold versus
  cold-then-cached, and does not re-run RowInv's fixed-prompt probe or its non-drafted arm.
- No fix is applied here. Whether the recipe export should stay (or the code default flip) is the owner's call; the
  measurement says the export is what turns the lever on.

## 5. State after the window

- Production restored inside the window's own hold: `prod /health 200 (start rc 0) image
  tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
  2026-11-22T04:26:16+00:00`; `docker ps` shows `qwen38-flash-next-tf` Up on that image, and no `gpu.lock` holder at
  04:26:57Z.
- sparkDash, read on Proxmox CT 111 at exit: **active**, `ActiveEnterTimestamp 2026-11-22 04:18:34 GMT`,
  `InactiveEnterTimestamp 2026-11-22 03:51:28 GMT`. It was started during the window by another actor; neither window
  touched it (the launcher's `DASH-STATE` records what was read at launch).
- Evidence: `work/PatchBisect/cost-evidence.tgz`, sha256
  `8028e6de17d2fc2ec58451ffbc577f945a7a902993285fc51a600145ffde2c6d`, equal on spark6 and the laptop; fetched into
  `work/PatchBisect/costbox` (see `FETCH-COST.txt`, `FINAL-STATE-COST.txt`). Both windows' `out/` logs are inside.
