# Parity campaign: upstream 1.2.4 to our 1.0.0-stack level, then upstream everything

Owner decision 2026-11-08: bring TensorFold 1.2.4 up to parity with our 1.0.0-based stack (the spark6
production serve), then upstream all of it to `ashhart/TensorFold`. The two levers already measured on
1.2.4 (the 48-row window, the copy re-sync) are the first two entries; the rest is the recipe's 17-patch
backlog minus what upstream already carries (docs/RECIPE-PATCHES-VS-UPSTREAM.md, docs/OPEN-PR-COVERAGE.md).

## The backlog, in port order (highest measured value first, checkpoint-agnostic items before INT4-bound)

| order | source (recipe v1.1.4) | measured gain (recipe CHANGELOG / our campaign) | checkpoint-agnostic? |
|---|---|---|---|
| 1 | **done** - 48-row window (`port-64rows-v2`, 6.5) | +26.6% copy, +12.2% rewrite | yes |
| 2 | **done** - copy re-sync + shared ramp (`port-copy-windows-ab4b2f05`, 6.2/6.8) | +66-67% rewrite stacked, +42-58% edits | yes |
| 3 | **done** - warm turns (`port-warm-turns`, 6.6) | next-turn TTFT -38-45% | yes |
| 4 | 0005 fp8 attention reader + MTP head cache | the v1.1.4 build's decode gains | kernel work, quant-shape dependent |
| 5 | 0006 prefill speed (no drain, vectorised hc) | prefill gains | kernel work |
| 6 | 0016 shared-expert side stream + lane-batched DeltaNet | the maintainer re-implemented part; verify what 1.2.4 has | partly upstream |
| 7 | 0010 n-gram gather all lanes at once | decode gather gains | yes |
| 8 | 0013 pread read-ahead + chunk-tail rule | prefill/decode IO gains | partly upstream (pread exists) |
| 9 | 0008 sampled GPU top-k | sampled decode | verify upstream's own |
| 10 | 0007 sampled streams in the batched head | sampled decode | verify |
| 11 | 0012 delta rollback folded into next verify (KEEP_LATE) | the late-log mechanism we measured | upstream has the constant, not the folding |
| 12 | 0014 prompt hc fusion | prompt passes | kernel work |
| 13 | 0015 prompt MX128 two-stage tile | prompt passes | kernel work |
| 14 | 0004 prompt expert tile | prompt passes | kernel work |
| 15 | 0009 round-cost model | scheduling | low priority |
| 16 | 0003 `--kv-cache fp8` for Flash Next | memory (5 windows fit) | INT4 checkpoint conflict - see below |
| 17 | 0001/0002 NVFP4 vision tower + 16k image tokens | vision serving | probably already upstream-adjacent |

## The checkpoint decision (open, measurement dispatched)

The current serve runs INT4-AutoRound; 1.2.4 refuses it and serves NVFP4. The quality comparison
(QualCompare124) decides: **NVFP4 acceptable** -> the backlog above ports as-is (no INT4 work);
**INT4 required** -> the old series' `0003-config-weights` loader (84k lines, the AutoRound g128
reader) and the int4 kernel families port FIRST, before items 4-16 (they consume the int4 layout).

## Protocol per port (proven this week)

One change per PR-branch from the same upstream tip; the boot-time self-check discipline for anything
that changes kernel shapes; lean base/head 0 new; host suite failing-lists identical; golden 6/6 and
reply-sha equality on every cell; ABBA, boot-split medians with group counts stated; memory lines per
boot; the fleet GPU protocol (announce, lock, restore serve+sparkDash, named timers). Upstream flow:
fork branch -> PR -> the receipt in `docs/receipts/<name>/`.

## Checkpoint route: DECIDED 2026-11-09 - NVFP4, no INT4 port

The quality comparison (QualCompare124, 30 identical prompts, both arms greedy): NVFP4 16/24 gradable
ground-truth passes vs INT4 15/24, the 3 disagreements single-item coin flips both ways. Long-context
recall is BYTE-IDENTICAL at 32k and 120k (needle, multi-hop, verbatim quote, config recall), exact-copy
identical, sampled prose clean on both arms. No failure mode unique to NVFP4. Stated confound: INT4 arm
= engine 1.0.0 + our levers + fp8 KV; NVFP4 arm = stock 1.2.4 + bf16 KV; 1.2.4 refuses INT4 so this
cross-engine pairing is the only possible comparison. Verdict: quality does not require porting the
INT4 loader/kernels to 1.2.4. The campaign is the decode levers only (items 4-17), and the serve moves
to NVFP4 when its parity is measured. Artifacts: spark6 `~/work/lanes/par114/quality/report.md`.

## ATC coordination - instrument and results (2026-11-09)

The `atc` CLI needs node + an authenticated `gh`; spark6 has neither. The instrument is the LAPTOP:
`C:/Users/Adam/atcboard.cmd` / `atcoverlapN.cmd` drive `npx --yes github:ashhart/ATC` via cmd.exe
(WSL cannot invoke npx.cmd directly - write a .cmd file), against the full clone
`C:/Users/Adam/Gitea/tf-atc-full` (a blobless clone breaks atc's working-tree read:
`workingTreeUnavailable`, changedFiles null). Per-port recipe: fetch the port branch into tf-atc-full,
`git checkout -B atc-<name> FETCH_HEAD`, run the cmd file.

- Board (`--repo ashhart/TensorFold`): coordinationEnabled=true, 199 open PRs, 51 contributors;
  `complete: false` (`pullFilesLimit`, `timeLimit`) so claim advice is unreliable - our levers have no
  issues to claim; the draft-PR route covers the claim per docs/atc/SKILL.md.
- 48-row branch overlap: 13 changed files, 142 PRs share >=1, **9 hard conflicts, all CHANGELOG.md**,
  0 code conflicts, 132 unknown (pullFilesLimit). JSON: work/atcoverlap3.json.
- Resync branch overlap: 21 changed files, 53 PRs share >=1, **1 hard conflict: #1394** (Llama2 DSpark
  drafting) on 2 paths of `core/lanes` - the known same-function sequencing case. JSON:
  work/atcoverlap4.json.

## Status

- Quality comparison: DONE - NVFP4 acceptable, no INT4 port (see above).
- Sequence-pool: measured negative (6.7).
- Item 4 (0005 fp8 reader + head cache): SPLIT by verification - 0005 builds ON recipe 0003
  (`--kv-cache fp8`), which introduces the KV8 kernel path and the fp8 Kv format that 1.2.4 does not
  carry (`zig grep KV8` on abc39af1b: absent; no `--kv-cache`, no fp8 in any flashnext kv file). The
  kernel half cannot port until 0003 does. The checkpoint-agnostic half DID port: the draft head's
  rows load 4-bit by default (recipe 0005's `TF_FLASHNEXT_DRAFT_HEAD` default flip; 1.2.4's
  `cuda_mtp_load.zig` had the affine4 path and the GLM family already packs its head 4-bit). One
  commit on `port-0005-reader` (signed b34f52952, base 267c5af6a): default_mode const + test moved
  into cuda_mtp_draft.zig after the mutant proved the test dead inside cuda_mtp_load.zig (its only
  importer references it inside a function body, so the test never enters the graph). Gates: fmt
  green; lean base/head 0 new (5768 files); host suite failing lists = stock three (listener Nagle +
  two drama_voice); mutant KILLED in a scratch copy. Overlap sweep: 6 open PRs touch the file, all
  add an EXL3 draft hook in `draft()`; none touch `mode()` - CLEAR. Gitea `ots/tensorfold-levers124`
  branch pushed; images up124/reader124 built on the nvcr pytorch base after the cleanup wave deleted
  every arm image (a PATH overlay re-adds the bare `tensorfold-native` the recipe's docker run
  resolves). A/B vs stock at 1/2/4/6 ABBA in flight; first cell reader124-c1 booted 40s, GOLDUP 6/6
  identical to zgold-up124.json.
- Item 4 A/B (2026-11-09, complete): reader124 vs stock up124, 12 ABBA cells, golden 6/6 every cell.
  Code +7.3% (s1) / +4.1% (s2) / +6.5% (s4) / +9.6% (s6); prose +9.9 / +2.9 / +4.6 / +9.7; rewrite
  probe +4.5%; model memory 76.16 -> 75.89 GiB. Negatives: the fp8 reader half is NOT ported (blocked
  on 0003); C=4/6 ran one boot each. BEFORE ITS PR: ATC overlap is already clear (the lane swept all
  202 open PRs - none touch mode()).
- THE STACK + SERIES (owner request 2026-11-09): FINAL - `levers124-stack` @ `fa4f6611` (12 signed
  commits on 267c5af6a: the 8 levers + 0026 round-cost + 0027 mx128 tile/records + 0028 compile
  repairs) and `levers124-series` @ `05a2bbcf` (11 patches, 0018-0028), both all-G signed, pushed to
  the Gitea fork; local `scripts/qwen38/zig/levers124/` holds all 11 + README, TREE_IDENTICAL +
  SERIES_EQUALS_STACK verified. The 0028 round is the campaign's gate catching what single-lever
  gates could not: a dropped `cap` in the kv8 squash's draft-KV pricing (an overflow on the first
  real draft), 9 defect groups total - repaired in 0028 (`4a446e3e0`), gates green (pr_check 0/0,
  host suite = stock three, kv8 + environment_test pass). The stacked A/B (stock124 vs stack124) is
  the migration gate, queued FIFO.
- THE STACK (superseded detail): branch @ `0b673402a`
  (16 signed commits on 267c5af6a) and `levers124-series` @ `7a5fb21ab`, pushed to the Gitea fork.
  Stacked clean: warm-turns, 0005-reader, 0006, 0010, 0013; resolved honestly: 0003-kv8 (5 commits
  vs its newer base). The series `scripts/qwen38/zig/levers124/0018-*.patch` .. `0025-*.patch` (8
  toggleable patches, numbering after the recipe's 0017) verifies: all 8 apply in order on pristine
  267c5af6a producing a byte-identical tree. SKIPPED pending their lanes' pushes: 0009-cost and
  0015-mx128 - they become 0026/0027 at PR time. The lane found and fixed real defects in the levers
  (0013 did not compile as committed - the missing ple_reader import + a duplicated cache region; the
  .word env kind absent at the older base), amended into the owning commits (own branches, no PRs,
  force-push announced). Stack gates: fmt green, pr_check 0/0 (lean 116 vs 116), host suite zero new
  beyond the stock three; the A/B window (stock124 vs stack124, 12-cell ABBA + golden + probes) is
  queued FIFO. The combined A/B receipt is the 1.2.4 serve migration's gate; after it, the settings
  retune runs on the stack.
- Item 7 (0010 n-gram gather): PORTED, correctness-clean, and PERFORMANCE-NEUTRAL at 1-6 streams
  (receipt 2026-11-09, 12/12 golden identical, the poff cell proving the default path stock-identical).
  The mechanism verified exactly (GATHER lines: 1 pool call per shared pass, gather 0.18-0.21 ms) but
  a shared pass holds 1.0 rows per lane window at PARALLEL<=6 - nothing to batch. The recipe's gain
  came from SSD-table reads + the 0013 pread path at higher concurrency; 0010 is the enabler knob for
  high-stream shared rounds. Verdict: carry behind the knob in the series (0024); the PR text (if
  posted) quotes neutral-at-1-6 + mechanism-verified, never a percent. Whether to spend upstream
  queue on a neutral lever is the owner's call - stated once, decision at approval.
- Item 17 (0001/0002 NVFP4 vision tower + 16k image tokens): PORTED AND GATED 2026-11-09 -
  the plan's "probably already upstream-adjacent" was REFUTED with evidence: 1.2.4's NVFP4 default is
  the LLM weights only; the vision tower decode is absent (loader expects .bf16 and fails closed on a
  quantized tower; zero nvfp4/mxfp8 hits in zig/src/vision), and 16k tokens is uncapped at 4096. The
  served checkpoint's tower IS quantized (MXFP8 attn.qkv/proj, NVFP4 mlp/merger). Ported as branch
  `port-vision-fp4` tip `fd0eafcde` (2 signed commits; qwen_cuda_dequant.zig + the linear() routing
  + max_image_tokens 16384 + a ModelOpt-fixture test), gates 0/0 + lean 0 new + host suite
  byte-identical, ATC zero code conflicts (6 PRs CHANGELOG-only). A/B window armed (vision-off golden
  6/6 byte-equal; base EXPECTED to fail the tower load - the refusal captured as the receipt's
  before-state; port answers the red probe + the 16,384-row probe).
- Item 9 (0008 sampled GPU top-k) RECEIPT 2026-11-09 18:38 (log-complete; its WINDOWDONE marker was
  dead from the morning kill list, touched 19:54): 6/6 golden identical on the sampled arm, sampled
  decode cells p8on/p8off within 0.2% at every level (no regression), 18 SAMPLED sha rows collected.
  VERDICT CLOSED 2026-11-09 (Port0008Topk final): 1.2.4 carries its own complete sampled top-k
  (fn_row_topk, the same two-pass histogram, TF_FLASHNEXT_GPU_TOPK default ON, topk_max 64) AND
  recipe 0007's gate (TF_FLASHNEXT_SAMPLED_HEADS) - items 9 AND 10 both close as covered. The
  sampled sha256 sets are IDENTICAL between arms on every (prompt, seed) pair (the candidate path
  draws the same bits); sampled decode settled ON 64.2-65.0 vs OFF 64.2-64.4 (not slower). The
  MISMATCH line was a bug in the lane's own bench harness (it compared a K-entry reference against
  44 memset-garbage slots) - fixed in the shipped bench source; NO kernel latencies were measured,
  so the recipe's 3x-faster claim stays unverified. One divergence NOT ported: NaN rows order
  above +Inf upstream BY DOCUMENTED CONTRACT (contract_flashnext_topk.zig) - the recipe's fallback
  would replace a contract-tested design. Verification receipt on the branch (`port-0008-topk`,
  badd33309, signed).
- Item 2 (copy re-sync) RECEIPT COMPLETE 2026-11-09 20:14, PR TEXT ASSEMBLED (restyle running):
  gitea `resync-on-48` = `cb32b158b` (G, YubiKey), sparkDash active, prod /health 200. Headline
  (up48/cw48): rewrite 254.3/377.7 (+48.6%), edit2 135.6/195.6 + 136.6/210.2 (+44.2/+53.9%),
  editprose edit 145.9/297.4 (+103.8%), prose 46.9/50.1 (+7%), copy 467.5/468.5 (flat), decode
  flat (six boots an arm), every workload sha equal, 0 failed/0 unmeasured. Stacked on the 48-row
  base (up48 254.3 vs the 32-row upab4 230.5: the wider window alone buys ~10%). PR text at
  upstream/tensorfold-pr-copy-resync-v2/PR_final.md - presented after the restyle + line review. the 12-boot 48-row matrix (12/12 golden
  6/6) + both arms' bench_concurrent; SIGNED push done - gitea `resync-on-48` = `cb32b158b` (G,
  YubiKey), sparkDash active, prod /health 200. Headline (up48/cw48): rewrite 254.3/377.7 (+49%),
  edit2 135.6/195.6 + 136.6/210.2 (+44/+54%), editprose edit 145.9/297.4 (+104%), prose 46.9/50.1
  (+7%), copy 467.5/468.5 (flat), decode flat, every workload sha equal, 0 failed/0 unmeasured.
  Stacked gain vs the 32-row base receipt (upab4/cwab4): rewrite 230.5/300.2 -> 254.3/377.7 - the
  resync compounds with the 48-row window as designed.
- Item 5 (0006 prefill speed) RECEIPT 2026-11-09 17:39: 12/12 boots, golden 6/6 every boot (the
  relaxed MXFP8 tile did NOT diverge). Cold prefill (fresh-prompt TTFT): +2.3% C1, +9.5% C2/4/6 on
  both 64k and 8k (the no-drain + 3072-chunk effect; 2k loses base's c1->c2 step). Decode TRADE
  FOUND: code +2.2%, prose -2.2% at EVERY level (consistent across 6 boots/arm + both clients) -
  per the fleet rule this is the owner's call UNLESS the staged bisect (TF_FLASHNEXT_PROMPT_MX128=0)
  recovers prose, in which case the tile goes opt-in and the PR presents a strict improvement.
  VmHWM equal, boot 34-38s, temps 54-69C. BISECT VERDICT 2026-11-09 20:32 (3 tile-off boots at
  C=1/2/6, golden 3/3 identical): prose RECOVERS to 46.21 mean (vs 44.9 tile-on, 45.9 base) - the
  relaxed MXFP8 tile CARRIES the prose delta; prefill keeps its gains with the tile off (64k 29.26 s
  = -7.8% vs base, BETTER than tile-on's -5.1%; 8k -3.3%, 2k -7.0%). ACTION: tile default OFF
  (opt-in TF_FLASHNEXT_PROMPT_MX128=N), re-gate, re-push - DONE 2026-11-09: `port-0006-prefill`
  new tip `6c53d7f05` (G, signed, branch grew), pr_check 0/0, host suite CONFIRMED TWICE (Port0006Prefill hostsuite-head2.txt + Port0050Upstream's
  independent run at 21:4x: 613/616 steps, failing list = stock three, 0 new, plus the four
  non-unit CI steps green - kernel-contract 236/236, golden 5/5, security 31/31, fuzz 21/21);
  the lane complete. Default-path
  numbers for the PR text (tile OFF vs stock e5889236b8): cold prefill 64k -7.8% at C>=2 / -1.5%
  C1, 8k -3.3 to -9.5%, 2k -7.0% at C>=2 (parity at C1); decode code +1.2-1.4%, prose +0.5-1.5%
  (NO trade); golden 15/15 boots identical. Tile-on is the documented opt-in (prefill a further
  0.7-2.2% faster, prose -1.4 to -1.7 at every level - the known cost). The 0006 PR text presents
  the default path with the opt-in note.
- Item 13 (0015 prompt MX128 two-stage tile): PORTED AND GATED 2026-11-09 - branch `port-0015-mx128`
  (3 signed commits on f212eeabd; substrate byte-identical to 0006's tile pieces - land 0006 first,
  then 0015 rebases to its delta). Gates: pr_check 0/0 (lean 0 new), host suite stock three + 2 new
  tests passing, contract records for all four prompt_mx kernels (128 regs two-stage, the minBlocks=2
  hint hit; missing stated: the FP64 reference + sm_80-89 audit rows). Receipt: golden 6/6 on all
  18 boots, g1 == g0 bit-identical (the same-bits claim verified), cold prefill -3.6% (64k) /
  -4.2% (32k) vs stock; the two-stage variant vs the 3-stage tile is timing-neutral end-to-end
  (the recipe's 61->76 TF is one projection shape, not whole-turn). Decode within noise.
- Item 15 (0009 round-cost model): PORTED AND GATED 2026-11-09 - one signed commit `88c8920d`
  pushed as `port-0009-cost` (12 files, +311/-61). The load-bearing finding: 1.2.4 has the row-pricing
  machinery (HeadCost.row_ms, row_cost.zig, observeOverhead) but NO price source for flashnext CUDA
  (facts() sets no shared_costs - the sweep machinery is Metal/qwen3_5-only), and upstream's learned
  fit cannot express A3's cheaper-draft-row model (it only charges more). Ported the recipe's
  cuda_round_costs.zig verbatim + facts() wiring + rateRows + forwardMs; knobs via strict-environment
  rows. Gates: fmt, pr_check 0/0, lean 0 new, host suite identical failing lists, 5/5 mutants killed,
  ATC 0 hard conflicts. A/B RECEIVED 2026-11-09 14:05 (window done, serve restored + health ok,
  14 GOLDCMP identical): the knob-liveness probes WORK - P1 (drafts priced out) decodes at
  fib 18.3 / chat 20.6 tok/s (plain-round speed) and P2 (priced in) at 72.3 / 46.1 (stock speed),
  golden identical in both - the allocator reads the table and routes correctly. Aggregate
  (bench_concurrent chat, stock9/port9): 1s 46.5/46.6, 2s 46.3/46.3, 4s 46.1/46.2, 6s 43.9/46.1 -
  neutral-to-slightly-positive; the lever's value is the SCHEDULING CONTROL (price drafts out under
  load, like the 6s cell already shows +2.2), not a raw gain at idle. Default knob off = stock.
- Item 16 (0003 `--kv-cache fp8`): PORTED 2026-11-09 (lane Port0003KV8; prove half with Port0003KV8b) -
  branch `port-0003-kv8` on spark6 `~/work/lanes/port0003/tf124`, commits `21356a9cb`/`fbd671349`/`9fb74d6ad` on
  upstream main `c5a044877`. Mapping: 1.2.4 already carries the flag plumbing (`engine_api.Open.kv8`, generic
  options/refusal gates), so the change is the family side; KV8 device code split into
  `zig/kernels/cuda/flashnext_kv8.cuh` (the 600-line lean rule forces it), sizes parameterized by `Heads`, fp8
  refused with pages/`--slide`/captured glue/tp=2/disk states (all new in 1.2.4, none combinable). 0005's reader
  half (`stage_kv8`/`kv8_widen8`) is in this change and closes 0005's blocked half. Gates: fmt clean; lean 0 new
  on every ported file (.cu exactly 600 lines, glue 600). Known defect for the next pass: the generated
  `stage_kv8_tile` body kept the lambda's `kc`/`vc` redeclarations - delete those two lines. With Port0003KV8b
  (live on the tree 08:07) or a re-dispatch: kernel-contract records (launch-record + FP64 reference, 4 kernels),
  `flock ~/work/gpu.lock`, Gitea push `ots/tensorfold-levers124`, ATC overlap. ATC overlap: CLEAR 2026-11-09
  (atcoverlap5.cmd, laptop recipe) - 25 changed files, zero hard conflicts against any open PR (the closest
  shares are 1-2 files at conflict "unknown" under the pullFilesLimit).
- COMPLETION (Port0003KV8b, 2026-11-09): all prove items done - the stage_kv8_tile junk lines fixed
  (+ HK parameterized), flashnext_kv8.cuh namespaced (the ambiguous decl/defn pair), the paged
  __shared__ table restored, the MISSING fn_attn_prep_media_kv8 defined (nvcc now compiles all four
  kernels for 5 SMs, rc=0), streamBytes pricing bf16+paged correctly (the underflow fix + test).
  Contract records wired into landed_cuda (4 launches, FP64 reference = the device test
  flashnext-kv8). fmt clean tree-wide (glue refactored to 599 lines), pr_check 0/0 (lean 398 vs 398),
  host suite failing lists byte-identical (the 13 extra head steps were GPU contention from the
  concurrent window, not failures). FIVE commits re-signed on the laptop, tree hash identical
  (89ae01af7), pushed as tip `7ff8292bc`; ATC overlap re-run: 27 files, 6 hard conflicts (5
  CHANGELOG-only, 1 adjacent test-import line vs #2475). A/B window armed (window_kv8.sh, 12 ABBA
  cells + the five-window memory claim, golden byte-equality as the storage-only check), queued on
  QUEUE.GO behind the 0050 window.
- Item 5 (0006 prefill speed): PORTED 2026-11-09 - branch `port-0006-prefill` = `fea018cc7` on the
  Gitea fork, base `e5889236b` (upstream main at clone time, post-1.2.4). Two pieces already upstream
  (vectorised hc, MoE memset skip); ported the relaxed MXFP8 prompt tile (bits differ from the exact
  kernels - golden is the test, bisect with TF_FLASHNEXT_PROMPT_MX128=0), the no-drain, chunk 3072;
  knobs via the lean-gate-compliant environment rules. Gates: fmt clean, pr_check 0/0, lean 398 vs
  398, host suite 1 new failure found and fixed (environment valid-list), full head re-run verifying.
  A/B armed (window_p6.sh), queued on the GPU lock. BEFORE ITS PR: the kernel-contract records
  (launch-record + FP64 reference, nvcc 13.0 sm_12x measured) for the two new kernels, and the ATC
  overlap (laptop recipe above).
- The 1.0.0-stack settings retune (CONFIDENCE / PRODUCT_STREAMS / PARALLEL / pool size on 1.2.4) is
  QUEUED BEHIND the port A/Bs, not parallel with them: tuning settings on a stock-engine baseline is
  throwaway - the ports change the picture. After the port windows drain, one ABBA settings sweep on
  the fully ported build, then the serve moves to 1.2.4 with its measured settings.
  STAGED 2026-11-09 21:42 (Port0015Mx128, window_retune.sh on spark6): the retune base is the
  stack migration's lever set (stack124's STACKENV verbatim - verified live: the COPY_* knobs route
  through the startup-phase flag() helper, GATHER_*/DRAFT_AHEAD in the rules), so the sweep isolates
  the production deltas ON the served config: R0 STACKENV; R1 STACKENV + CONFIDENCE=-0.15 +
  DEPTH=15 + PREFILL_TAIL=512 (the only m8env knobs the stack implements - PRODUCT_STREAMS/pool/
  WINDOW absent from 4a446e3, recorded N/A); R2 CONFIDENCE-only. c1/c2 ABBA, c4/c6 reversed, c8
  R1-only at CONTEXT=98304 (8-stream scratch fit) with levels 1,2,4,6,8; ~15 boots; gated on a fresh
  stack124 WINDOWDONE then FIFO; restore qwen6-start-prod.sh + /health.
- THE KINDLING HANG (owner directive 2026-10-26): CLOSED + UPSTREAM SUBMISSION STAGED 2026-11-09.
  0050 boot-verified (five clean boots 59-83 s, all gates green); the upstream lane then found the
  premise stale - current main 23b69e25e ALREADY stages DeviceBuffer.upload through anonymous memory
  (upstream e9bf05ffd, 2026-10-17) - and audited every cuMemcpyHtoD_v2 site: ONE residual live
  defect-class site (minimax_m3/cuda_vision.zig Tower.up passing checkpoint mmap bytes straight to
  the driver). The submission is that one-commit fix (branch fix-upload-staging = 9bee291f0, signed,
  gates 0/0 + all four non-unit CI steps green, ATC clear, boot-verified on kindling: base and head
  both 34 s with golden 6/6 identical). PR TEXT PENDING: restyle + owner approval.
- THE KINDLING HANG (the fix evidence, superseded detail): CLOSED 2026-11-09. 0050 (every blocking H2D upload
  staged through a pinned 1 MiB stack block in zig/src/cuda/memory.zig) boot-verified on kindling:
  five consecutive clean boots 59-83 s through the checkpoint load that previously spun forever, ALL
  fp4chain2 gates green (int4v/int4b golden 6/6 + exact; nvfp4d/e/f exact + toolcheck/needle/sampled/
  prefill; nvfp4 golden exit-1 expected, no FP4 ref on kindling). Evidence:
  ~/work/gpuev/runs/fp4-*/hold.log + HANDOVER.md 2026-11-09. REMAINING: the upstream submission of the
  fix (text drafting + restyle + approval).
- Item 6 (0016 shared-expert side stream + lane-batched DeltaNet): NO-OP, verified 2026-11-09
  (Verify0016Shared) - upstream 1.2.4 carries BOTH mechanisms, default-on, with contract proofs:
  lane-batched DeltaNet via 15f118ab6/4fb2f65ef (superset: 16 lanes, one unified log + ctl, optional
  per-lane logs, contract_flashnext_lanes.zig 435 lines) and the shared-expert side stream via the
  #1763 merge + 52b9f90a4/12e0e57f0/2a92fb6c9 (superset: the strided direct down generalizes the
  recipe's direct idea, plus a TP split_shared gather the recipe never had). Only two recipe-only
  debug knobs absent (SHARED_SIDE_PRIO/POISON). Our 1.2.4 move gets 0016's gains free. The stale
  note ("maintainer re-implemented part") undercounted: it is a full superset.
- Item 11 (0012 delta rollback): NO-OP, verified 2026-11-09 (Port0012Delta) - upstream 1.2.4 carries
  the complete KEEP_LATE folding (merged 2026-11-02 as #1763), DEFAULT ON at TP=1: our serve gets it
  free on the 1.2.4 move. The stale campaign note came from a signature-shaped grep - 1.2.4's
  `gdn_rows_late` has a different signature than the recipe's, and the qwen3_5 family's
  `TF_QWEN_KEEP_LATE` really is constant-only. The only 0012 residue absent is its standalone GPU test
  script; 1.2.4 proves the same property with per-kernel contract tests.
- Item 10 (0007 sampled streams in the batched head) WAITS for item 9's verdict (Port0008Topk): both
  touch the same sampled-decode area, and if 0008's mechanism is already upstream, 0007 is likely moot.
  No new port lanes until the GPU window queue drains - the CPU ports finish long before their A/B
  windows run, so the remaining items (0007, 0014, 0015, 0004, 0009) dispatch as lanes free up.
- Everything else: queued in the order above.
- Item 13 (0015 prompt MX128 two-stage tile): PORTED and MEASURED 2026-11-09 (Port0015Mx128) - branch
  `port-0015-mx128` on gitea `ots/tensorfold-levers124`, signed `a9a70a173`/`a5aac174d`/`c747816fa` on upstream
  main `f212eeabd`. Mapping: NOTHING of 0015 is in 1.2.4 - no MXFP8 prompt tile at all (upstream has the BF16
  128x128 3-stage tile + K32 prompt kernel only, no `cuda_knobs.zig`); the substrate is exactly recipe 0006's
  tile, so commit 1 re-lands the sibling's `port-0006-prefill` tile pieces BYTE-IDENTICAL (verified empty
  `git diff` on qmmf.cu/qmmf.zig/cuda_tiles.zig) and commit 2 is 0015's delta (`TF_FLASHNEXT_PROMPT_GEMM2`:
  two stages, two blocks an SM, same arithmetic and bits) + nvcc-13.0 contract records (175/128 regs,
  sm_120/121; the two-stage variant compiles to exactly the 65536-reg file two blocks need). Sibling overlap:
  8 of 10 files shared with port-0006-prefill - PR-time sequencing: land 0006 first, then 0015 rebases to its
  delta; if 0015 lands first, 0006 drops the tile pieces. ATC: 10 changed files, 5 hard conflicts all
  CHANGELOG.md, zero code. Gates: fmt clean, pr_check 0/0, lean 398 vs 398 (0 new), host suite failing lists
  identical to stock, +2 tests passing. Receipt (spark6 `~/work/lanes/port0015/REPORT-P15.txt`): golden 6/6
  on EVERY boot of all three arms (base 6 boots, port 12 boots) and g1 == g0 bit-identical on every g1 boot
  (0015's same-bits claim holds); cold prefill (arm medians, n=6): 64k 33.752 -> 32.522 s (-3.6%), 32k
  16.447 -> 15.750 (-4.2%), 8k -3.4%, 2k -3.6%; the two-stage variant vs the 3-stage tile is timing-neutral
  end to end (<=0.013 s at every size; the recipe's 61->76 TF is a kernel microbench at one shape); decode
  and concurrent within noise; VmHWM 6.80-6.83 GiB both arms, temps 51-68C. Checkpoint note: the NVFP4
  checkpoint's GDN/attention projections are MXFP8 native (weight+weight_scale), so the tile routes; experts
  are nvfp4 and do not. Deviations: window B's port cells failed on an arm-name/image-tag mixup (rebuilt as
  window C, base data valid); build-br.sh was edited mid-build by another lane, crashing my wrapper after
  the image tagged (p15base needed a 2-s PATH-overlay patch - same fix sent to Port0006Prefill for p6base);
  the FP64 reference + served envelope for contract gates 1-4 are NOT done (upstream's prompt records carry
  the same shape: launch receipts only, sm_80-89 audit entries pending).

## CONTRIBUTING requirements verified 2026-11-08 (the full file read)

- **ATC coordination is mandatory**: check the agent radar before choosing an issue, claim via ATC,
  `atc overlap --json` before opening a PR, publish the session, pulse while working. Agents read
  `docs/atc/SKILL.md`. Our two staged levers have no claimed issue - the 48-row and resync PRs each
  need an ATC claim (or an issue first for the arithmetic-change rule; a copy-window width and a
  proposer policy are kernel/behaviour changes, so an issue is the safer route for both).
- **Performance receipts in their format**: `tools/bench_openai.py` and `tools/bench_concurrent.py`
  with `--alone --serial`, 256 tokens, 3 reps, temperatures 0 - which the 48-row receipt already ran
  (bench64, both arms, the JSONs on the branch). Cold prefill: exact 2k/8k/32k/64k token arrays.
  Compare against the previous release AND the applicable standard server; alternate before/after runs
  for few-percent differences (our ABBA order satisfies this).
- **Memory receipts**: peak physical process footprint + device/pinned allocations, the hardware RAM
  class, one model process per machine, the existing GPU lock. Our boot-line records satisfy the
  device part; VmHWM should be added to the next window.
- **Kernel contract**: a changed GPU kernel registers with `docs/kernel-contract.md` and the PR posts
  each backend's SUMMARY line - this binds the 48-row window (its kernels changed shape) and would
  bind any int4 kernel port. The FP64-reference rule binds any changed reduction order.
- **The lean gate**: `tools/zig/lean_check.py` (0 new), plus `tools/pr_check.py --base origin/main
  --pr NUMBER` before pushing - a tool we have not been running; add it to the pre-post checklist.
- **Public identity**: the approved noreply address (`598804+BadAd84@users.noreply.github.com`),
  no machine names/local paths - as our texts already comply.
- **One change per PR, main is the only branch** - matches our one-lever-one-branch flow.
