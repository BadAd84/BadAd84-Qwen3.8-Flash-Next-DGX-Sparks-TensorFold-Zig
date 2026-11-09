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
- THE KINDLING HANG (owner directive 2026-10-26): CLOSED 2026-11-09. 0050 (every blocking H2D upload
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
