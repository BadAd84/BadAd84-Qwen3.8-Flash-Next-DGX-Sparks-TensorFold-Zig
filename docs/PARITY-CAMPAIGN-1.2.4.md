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

- Quality comparison: in flight (QualCompare124) - decides the checkpoint route.
- Sequence-pool: measured negative (6.7).
- Item 4 (0005 fp8 reader + head cache): port in flight (ReaderP5Port, branch `port-0005-reader`,
  image `reader124` when built) - the first kernel-level parity port.
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
