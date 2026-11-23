# Triage of patches 0001, 0002, 0009, 0016, 0010, 0011, 0013, 0018 for upstream TensorFold

Written 2026-11-16. Triage only: nothing posted, pushed, compiled or run on a GPU.

**Base used for the whole file (T):** `077998f7d9b14adebec3a2acc2caa47ff7ae6ec7`, "changelog: #3572 under Unreleased",
2026-11-16 15:26:10 +0000, from `git -C work/upmain fetch origin main` at 2026-11-16 17:25:15 UTC.
Our series' own base is `964174ea05879e6dde1de1198a3aae3ef8b46a3b` (v1.2.9-33-g964174ea05, 2026-11-15 12:43:19), which
is an ancestor of T; 153 commits separate them.

**Worktree:** `work/Triage-Rest/base`, `git worktree add --detach ../Triage-Rest/base 077998f7d`, reset to T between
every case. A second worktree, `work/Triage-Rest/pf` at `02a2b6544` (the head of PR #3413's branch
`flashnext-readout-fused`), was used for the 0018 stacking question.

## Verdict summary

| patch | lever | files/lines | applies on T | verdict |
|---|---|---|---|---|
| 0001 | lone stream's copy window to the boot self-check's largest row-exact width; row-by-row DeltaNet for a log-carrying window | 10 / +130 -24 | 3-way clean, one rule row re-seated | **SUBMIT** (rank 2) |
| 0002 | copy resync past an edit, the copy ramp and miss rules, lane core config | 8 / +308 -20 | clean | **RETIRE** (no measured gain; five new getenv settings) |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy (`TF_FLASHNEXT_HC_Q12`) | 10 / +559 -8 | clean after 0001..0007 | **HOLD** (capacity cost, no served gain outside noise) |
| 0016 | 0009's 12-bit read-out tile loads two groups ahead | 2 / +31 -13 | clean after 0009 | **HOLD** (follows 0009) |
| 0010 | a shared round priced from the environment (`TF_FLASHNEXT_ROUND_MS`, `DRAFT_ROW_MS`) | 13 / +312 -61 | conflicts in the lane core (#2687) | **RETIRE** (superseded by #2687, and measured inert) |
| 0011 | vision tower linears decoded at load, image rows to 16,384 | 8 / +449 -7 | code clean, CHANGELOG only | **SUBMIT** (rank 3; capability, no speed stake) |
| 0013 | the window self-check logs its first differing row | 1 / +9 -1 | clean after 0001 | **HOLD** (fold into 0001 or keep downstream; not a PR) |
| 0018 | the read-out's reduce and mix inside its products (`TF_FLASHNEXT_READOUT_FUSE`), decode | 10 / +368 -4 | one environment hunk after 0001..0007 + 0017 + 0009 | **SUBMIT** (rank 1), as the follow-up #3413's maintainer asked for |

Ranked by expected gain on the owner's workload (decode at 2 to 8 streams and cold prompts on one GB10):

1. **0018**: +1.8% at 8 streams in our only measured cell (with `HC_Q12=1 FUSED_SPLIT=1`), inside cell noise at 1, 2
   and 4; prompts unchanged by construction. Its BF16-only arm at 6 and 8 streams has never been measured, which is
   the first receipt to take.
2. **0001**: zero on the stated workload (single-stream copy proposals only; shared rounds keep `first_copy`), and
   +26% / +12% on copy tasks (a verbatim copy and a one-word rewrite of ~1,800 tokens). Those are the edit and rewrite
   turns our agents do, but they are not decode at 2 to 8 streams.
3. **0011**: no speed claim at all. It makes `--vision` load the FP4 checkpoint's ModelOpt tower; our recipe runs
   `VISION=0`.

## Commands and their decisive output

    $ timeout 90 git -C work/upmain fetch origin main | tail -1
    From https://github.com/ashhart/TensorFold
     * branch                main       -> FETCH_HEAD
    $ git -C work/upmain log -1 --format='%H %ci %s' origin/main
    077998f7d9b14adebec3a2acc2caa47ff7ae6ec7 2026-11-16 15:26:10 +0000 changelog: #3572 under Unreleased

### Apply matrix, `git apply --check` into a pristine worktree of T (passes A to O, then refinements)

    [A] TARGET 0001-rows: CONFLICT (prereqs: none)
    error: patch failed: zig/src/platform/environment.zig:50
    [B] TARGET 0002-copy-resync: CLEAN (prereqs: none)
    [D] TARGET 0009-readout-q12: CONFLICT (prereqs: none)
    error: patch failed: zig/src/families/flashnext/cuda_prompt.zig:12
    [F] TARGET 0010-round-cost: CONFLICT (prereqs: none)
    error: patch failed: zig/src/core/lanes/allocate.zig:47
    error: patch failed: zig/src/core/lanes/depth.zig:480
    error: patch failed: zig/src/core/lanes/windows.zig:292
    error: patch failed: zig/src/families/flashnext/cuda_lanes.zig:8
    [H] TARGET 0011-vision: CONFLICT (prereqs: none)
    error: patch failed: CHANGELOG.md:51
    [I] TARGET 0013-check-log: CONFLICT (prereqs: none)
    error: patch failed: zig/src/families/flashnext/cuda_mtp_check.zig:205

Three-way pass, then with the real predecessors:

    3way 0001-rows: MERGED CLEAN
    3way 0009-readout-q12: rc=1 conflicted=[cuda_prompt.zig]      (alone: needs 0005's import line)
    3way 0010-round-cost: rc=1 conflicted=[CHANGELOG.md allocate.zig depth.zig windows.zig cuda_lanes.zig]
    3way 0011-vision: rc=1 conflicted=[CHANGELOG.md]              (all code clean)
    check 0013-check-log after 0001: CLEAN
    check 0016-readout-q12-ahead after 0009: CLEAN

Series in order on T, CHANGELOG excluded (pass 4):

    0001-rows: ok   0002-copy-resync: ok   0003-kv8: ok   0004-ngram-row-cache: ok
    0005-prompt-chunk: ok   0006-prompt-gemm2: ok   0007-draft-head-4bit: ok
    0008-prompt-readout-fused: FAILED unmerged=[environment.zig environment_test.zig]
    check 0009 after that: CLEAN          check 0016 after 0009: CLEAN
    check 0018 after 0009: CONFLICT (qmmf.zig:198, cuda_knobs.zig:94, cuda_prompt.zig:152, environment.zig:66)

Definitive conflicts after the real prerequisites (pass 5):

    check 0010 after 0001..0007: CONFLICT (CHANGELOG, allocate.zig:47, depth.zig:480, windows.zig:292)
    0017 on T after 0001..0007: applied
    check 0018 after 0001..0007 + 0017 + 0009: CONFLICT, environment.zig:66 only
    check 0016 after the same chain: CLEAN

On PR #3413's head `02a2b6544` (pass in `work/Triage-Rest/pf`):

    check 0018: CONFLICT (qmmf.cu:8, qmmf.zig:198, qmmf_q12.zig missing, cuda_batch_hc.zig:101,
                          cuda_batch_kernels.zig:161, cuda_knobs.zig missing, cuda_prompt.zig:152)
    check 0009: CONFLICT (cuda_prompt.zig:12 only)

### Absorption search on T

    $ for s in TF_FLASHNEXT_WINDOW_CHECK TF_FLASHNEXT_HC_Q12 TF_FLASHNEXT_ROUND_MS TF_FLASHNEXT_CHECK_LOG \
               TF_FLASHNEXT_READOUT_FUSE TF_FLASHNEXT_READOUT_FUSED resync qmmf_q12 served_rows probeServed; do
        grep -rl "$s" zig/ docs/
      done
    TF_FLASHNEXT_WINDOW_CHECK        (nothing)
    TF_FLASHNEXT_HC_Q12              (nothing)
    TF_FLASHNEXT_ROUND_MS            (nothing)
    TF_FLASHNEXT_CHECK_LOG           (nothing)
    TF_FLASHNEXT_READOUT_FUSE        (nothing)
    TF_FLASHNEXT_READOUT_FUSED       (nothing)
    resync                           (nothing)
    qmmf_q12                         (nothing)
    served_rows                      (nothing)
    probeServed                      (nothing)

    $ grep -n "pub const max_rows" zig/src/families/flashnext/cuda_mtp.zig
    84:pub const max_rows: usize = 32;
    $ grep -rn "window self-check|probeServed" zig/src        (nothing: no self-check exists upstream)
    $ sed -n '259,265p' zig/src/families/flashnext/cuda_batch.zig
    const fused = self.lanes.len == 0 and (n >= 64 or marks.inPass(self)) and self.k.forms.gdn_fused;
    const cuts = try marks.cuts(self, li, fused);
    if (fused and keep.log != 0) return error.UnexpectedTensor;
    $ grep -n "copy_width = if" zig/src/core/lanes/*.zig
    engine.zig:294: s.copy_width = if (own_kept == own) @min(e.cfg.max_copy, 2 * width + 1) else e.cfg.first_copy;
    $ git diff --stat 964174ea05 077998f7d -- zig/src/cuda/qmmf.zig zig/src/families/flashnext/cuda_prompt.zig
    (empty: no upstream drift in either file)
    $ git log --oneline --diff-filter=A -1 -- zig/src/core/lanes/shared_price.zig
    0c8a9e3db Price shared plain rounds independently of drafted row costs   (2026-11-16 00:01:26 +0000)

---

## 0001: a lone stream's copy window to the boot self-check's largest row-exact width

**1. Applies on T?** Not by plain `git apply --check`: one hunk, `zig/src/platform/environment.zig:50`, where upstream
added `TF_CACHE_EVICT` and `TF_SHARED_PRICE_LOG` rows since our base. `git apply --3way` merges with no conflict
markers, and every other file in the patch (10) applies untouched, including `cuda_mtp_check.zig`, the new
`probeServed`/`windowCheck`, `cuda_mtp.zig`, `cuda_lanes.zig`, `cuda_lanes_load.zig`, `cuda_batch.zig`. So the re-seat
is one row in a rule table.

**2. Absorbed upstream?** No. T has `max_rows = 32`, no `TF_FLASHNEXT_WINDOW_CHECK`, no `probeServed`, no self-check
log anywhere in `zig/`. v1.2.8's #2934 is row padding, not this window, as `patches/main-964174ea05/RECORD.md` records it.

**3. What it changes at run time.** For a lone drafting stream on one GPU, the copy window's width becomes the largest
width the boot self-check proved row-equal (48 on GB10) instead of 32, and the draft buffers grow to 64 rows to be able
to measure 64. Shared rounds are untouched: `first_copy_rows = max_chain + 1 = 16` still bounds them, and the ramped
width is only used when `e.alone`. The second change is a path fix: a verify window carrying a pending-row log takes
the row-by-row DeltaNet instead of returning `error.UnexpectedTensor` from the fused path (T's `cuda_batch.zig:263`).
Replies stay byte-identical **only because of the self-check**: it compares each width's rows to their one-token steps
byte for byte on a synthetic 96-token prompt and serves the proven prefix; a copy is a proposal either way, so the
verified rows decide. The default path is not exact by construction, it is exact because the check measures it, which
is why the check is load-bearing rather than diagnostic.

**4. Upstream-ready?** Not yet. Required changes, in order of seriousness:

- **The off and failure paths change tokens.** `served_rows` starts at `max_rows = 64`, the `catch` branch sets it to
  `mtp.max_rows` (64) and only warns, and `TF_FLASHNEXT_WINDOW_CHECK=0` skips the probe with no assignment at all. So
  with the check off or failed, the engine serves 64-row copy windows **unprobed**, and on GB10 widths past 48 have
  rows that differ from their one-token steps (the boot log's 1,176 of 2,080). That is an opt-in mode that changes
  output tokens, which upstream refuses outright ("no mode that changes output tokens, even opt-in"). The fix is one
  line of policy: default `served_rows` to 32 (the width T ships), and on a failed or skipped check serve 32, never 64.
  Then the setting's off state is exactly today's behaviour and "new things default off" is satisfied.
- **A device test is missing.** The self-check is device code (`cuda_mtp_check.zig`) with no test that runs it, and
  upstream requires each new test to be shown failing first. The right shape is the one #3413 used: a `zig/tests/cuda`
  file that runs the width sweep and asserts row equality at the served width, plus a planted control (a width past
  the served one must differ on GB10).
- **New setting:** `TF_FLASHNEXT_WINDOW_CHECK` (flag, default on), already read through `platform/environment.zig` with a
  rule and an `environment_test` case. That part is in the upstream shape.
- **No kernel-contract entry needed**: no new GPU kernel, only a host choice between two existing paths and a reuse of
  `verify` plus `download`. There is no planted control to write.
- **Size and shape:** 10 files, +130/-24. It is one behaviour (the copy window's width is proved, not assumed) with a
  prerequisite fix (the log-carrying window's DeltaNet path) that the check cannot run without. Keep them in one PR and
  say so in the body; splitting leaves an intermediate tree where the check cannot measure widths of 64.
- **Device memory cost:** the draft buffers go from 356,905,472 to 411,436,032 bytes (full heads, +52.0 MiB) and from
  280,191,488 to 315,737,088 (half heads, +33.9 MiB), and the saved rows double (41,021,440 to 79,646,720 full,
  20,930,560 to 40,570,880 half). This is a capacity cost paid on every boot, and it belongs in the body.
- **CHANGELOG:** the patch's bullet carries the placeholder `#9999`; it needs the issue and PR numbers.

**5. Our evidence so far.** `patches/1.2.6/README.md:21`: "copy windows up to 64 rows, with the boot self-check that
serves the largest row-exact window (48) ... exact; decode flat (-0.3%); **copy workload +26% / +12%** (375.0 to
472.7 and 228.6 to 255.9 tok/s on a verbatim copy and a one-word rewrite of a ~1,800-token text, replies identical)".
`patches/main-964174ea05/README.md:79` and every 1.2.7 cell: "window self-check: 1176 of 2080 rows byte-equal to their
one-token steps (widths 1-64)". `docs/CATCHUP-1.2.6.md:71` records the defect this lever has to survive: windows
falling back from 48 to 32 rows, "0 of 2080", whenever a later patch moved the chunk position.

**6. Receipt on T.** One GPU window, one pass a cell, fresh boot a cell: decode at 1, 2, 4, 6 and 8 streams, two arms,
10 boots; the copy cells the gain lives in, a verbatim copy and a one-word rewrite of ~1,800 tokens, two arms, 4
boots; then repeats (two runs an arm) on every cell inside noise, which for decode will be all of them, so budget 20
boots and two windows if the noise rule demands it. Add the exactness contract on both arms (drafted equals
`"draft": false`, resumed prompt equals fresh, `tools/bench_concurrent.py --levels 1,4 --alone --serial`), one cold
prompt pair to show no change, and the boot-time delta of the check, which we have **never measured** and which a PR
must state.

**Verdict: SUBMIT.**
- Issue: needed (the copy-window width and the boot self-check are a new behaviour; the issue is also the agreed gate).
- Branch: `flashnext-window-check`, cut from upstream main at T.
- Patch list: 0001 only, with the off/failure policy fixed to serve 32, a `zig/tests/cuda` device test for the sweep,
  and the CHANGELOG bullet numbered.

## 0002: copy resync past an edit, the copy ramp and the miss rules

**1. Applies on T?** Clean, on its own and after 0001 (`git apply --check` returns 0). It touches no file 0001 touches.

**2. Absorbed upstream?** No. T keeps the old ramp verbatim at `engine.zig:290-295` (`if (e.alone) ... 2 * width + 1`)
and `windows.zig:205` (`if (e.alone) (s.copy_width orelse first_copy) else first_copy`). There is no `resync` field,
no `resyncFrom`, no `copy_miss`/`copy_ramp`/`copy_shared` in `core/lanes`.

**3. What it changes at run time.** Nothing by default: `copy_miss = .first`, `copy_ramp = .double` and
`copy_shared = false` reproduce the existing rule line for line (the `rampCopy` move from `engine.zig` to
`windows.zig` is a refactor), and `resync = false` leaves `SuffixLookup` untouched apart from the `index.get` if-let
rewrite. With `TENSORFOLD_COPY_RESYNC=1` (or `COPY_MISS`/`COPY_RAMP`/`COPY_SHARED`) it changes which tokens are
**proposed**: `resyncFrom` returns a source position past an edit and `s.out` is filled from it, `rampCopy` changes
only `copy_width` and `copy_prompt`, and `copyProposal` only chooses a width. No verify row path is touched:
`observe` books counters, the history is read, nothing writes `d.logits` or the row set. Replies are byte-identical by
construction for that reason (a proposal is checked by the verify forward), provided the verify path itself is exact,
which is 0001's business.

**4. Upstream-ready?** No, and the blocker is not fixable by re-seating:

- **No measured benefit.** `patches/1.2.6/README.md:22`: "exact; decode flat; copy workload 472.7 to 470.8 and 255.9 to
  255.0 with it (no gain beyond 0001 on these two texts)". `patches/1.2.7/README.md:158`: "**The copy policy does not
  move it either.** `TENSORFOLD_COPY_MISS=keep`, `COPY_RAMP=jump`, `COPY_SHARED=1` and `COPY_RESYNC=1`, alone and
  together, at one and four streams: every cell returns the default counters to the digit and the same speed inside
  noise." Upstream's rule is that a switch arrives with a measured benefit; this one has four settings and none.
- **Five new `getenv` settings outside `platform/environment.zig`** (`TENSORFOLD_COPY_MISS`, `_RAMP`, `_SHARED`,
  `_RESYNC`, `_RESYNC_PROMPT_ONLY`, read in `native/cuda_startup_phase.zig` through `cuda_device.getenv`). Upstream's
  rule: a new setting goes through the environment table, and "a new `getenv` is a lean finding".
- **Three behaviours in one patch** (resync; the ramp and miss policy; the env plumbing), 8 files and +308/-20 of the
  lane core, which every family shares. If any part goes up it is two PRs, and only resync has a story that could be
  measured on a different workload.

**5. Evidence.** The two quotes above, plus `1.2.6`'s measurement method (a verbatim copy and a one-word rewrite of
about 1,800 tokens at one stream, replies identical). Nothing shows resync firing at all: identical counters means the
proposal stream did not change, so the workload never exercised it.

**6. Receipt if it were revived.** It needs a workload where resync fires (an agent rewriting its own copied block, not
a verbatim copy), counters that show a different proposal stream, and then decode plus copy cells at 1 and 4 streams,
two arms, two runs an arm. One window, but the gain has to exist before the window is worth spending.

**Verdict: RETIRE** from the upstream queue (obsolete: no measured gain on either workload, and its settings shape
breaks the environment rule). Keeping it in our own series is the owner's call; as an upstream candidate it is not
submittable as measured.

## 0009 and 0016: the read-outs' lossless 12-bit copy, and its two-group prefetch

**1. Applies on T?** 0009 alone fails at `cuda_prompt.zig:12` because that hunk needs 0005's import line; after
0001..0007 (three-way, CHANGELOG excluded) `git apply --check 0009` is **CLEAN**, and after 0009, 0016 is **CLEAN**.
Neither needs any hand re-seat: T has no drift in `cuda_prompt.zig` (`git diff --stat 964174ea05 T` is empty for it)
and the q12 kernel/Rust-side files are all new.

**2. Absorbed upstream?** No. T has no `qmmf_q12`, no `zig/src/cuda/qmmf_q12.zig`, no `TF_FLASHNEXT_HC_Q12`, and
`zig/src/vision/` is unchanged since our base.

**3. What it changes at run time.** With `TF_FLASHNEXT_HC_Q12=1` the two read-out matrices are copied at load into a
lossless 12-bit form (a sign and mantissa byte a weight, 4-bit exponents, exact escapes; the loader reads each copy
back and checks it equals the BF16 weights) and decode read-outs read the copies instead of BF16; 0016 issues each
group's block loads two groups ahead of their use. Both are exact by construction (no product, no rounding, no
addition order changes; 0016 is load scheduling only), and both were proven by reply hashes. No served path changes
without the setting.

**4. Upstream-ready?** In principle yes: it is a **lossless** weight copy, not a lossy format, so it does not hit the
rule that bars those. What it needs: `TF_FLASHNEXT_HC_Q12` read through `platform/environment.zig` (today `on()` in
`cuda_hc_q12.zig` uses `std.c.getenv`, a lean finding); kernel-contract registration for the new Q12 qmmf instances
(16 and 32 row tiles, half tiles, plus the reduce) with planted controls; a device test that reads a copy back
(0016 changes `warp_tiles` into `warp_load`/`warp_decode`, so the existing round-trip test in `qmmf_q12.zig` covers
it, but the tile needs its own contract). 0009 is 10 files, +559/-8; 0016 is 2 files, +31/-13. 0016 has no switch of
its own and cannot ship before 0009.

**5. Our evidence, and why it is HOLD.** `patches/1.2.7/README.md:350`: "Each alone moves less than the ~1% cell
noise: `HC_Q12=1` reads 0.0% / -0.3% at six and -0.3% / -0.4% at eight". `README.md:353`: "the 12-bit copies take
1.07 GB of device memory (the boot line's model 73.29 to 74.31 GiB)". `README.md:402`: "shows no served gain outside
the noise at 1 to 4 streams. `HC_Q12` cannot flip either: its 1.02 GiB is a capacity cost, which counts as a
regression." `patches/main-964174ea05/README.md:48`: "`HC_Q12` is the one switch the block leaves out: its 1.02 GiB
of 12-bit copies is a capacity cost (14 pool pages, 57,344 positions, fewer at 6 and 8 streams) and it showed no
served gain outside the cell noise at 1 to 4 streams." 0016's own contribution: "Two groups ahead moved the down from
41.0 to 40.2 us and the up not at all" (`README.md:356`).

**6. What would change the verdict.**
- A served gain outside the noise at 1 to 4 streams, or any gain at 6 and 8 (today it loses 0.3% to 0.4% there), with
  two runs an arm.
- The capacity cost going away or shrinking: the copies are a second full copy of the matrices in device memory, so
  reading the 12-bit form straight from disk (as the n-gram table does) or sharing the copy with another consumer
  would change the trade. A checkpoint with larger read-out matrices moves it the same way.
- A served workload where the read-out is a bigger share of the round, which is not this engine: the kernel table
  (`README.md:376`) puts the whole read-out at 9.9 ms of a 69 ms round.
- An upstream request for the mechanism itself (a lossless narrower weight store is a plausible standalone idea), in
  which case it goes up as a mechanism PR with no served claim.

A PR receipt, if the verdict changes: the same 1, 2, 4, 6, 8 stream cells, two arms, two runs an arm (2 windows), the
kernel contract run, and a memory line per boot. **Verdict: HOLD**, 0009 and 0016 together, blocked by the capacity
cost against no served gain.

## 0010: a shared round priced from the environment

**1. Applies on T?** No. After 0001..0007, `git apply --check` fails at `CHANGELOG.md`, `allocate.zig:47`,
`depth.zig:480` and `windows.zig:292`; alone it also fails at `cuda_lanes.zig:8` and `environment.zig:49`. This is
real drift, not series coupling: #2687 rewrote exactly those three lane-core files.

**2. Absorbed upstream? Partly, and superseded in method.** Upstream landed the shared-round price itself, measured,
under #2687: 13 commits from `0c8a9e3db` "Price shared plain rounds independently of drafted row costs" through
`e872da389` "lanes: retain signed learning with independent plain prices", plus two follow-ups (`acbbbfd12`,
`029f8139d`), all on 2026-11-16, adding `shared_price.zig` (95 lines), `shared_round.zig` (111), `price_log.zig` (73)
and their tests, and removing 70 lines of the old path from `engine.zig`. Its CHANGELOG line at T:

> Lanes: shared rounds price a plain (undrafted) round apart from drafted rows, from trial rounds whose first is a
> dropped warm-up, and fit row costs from plain and drafted widths, so only how many drafts a round asks for changes;
> on gfx1151 with Qwen3.6-35B-A3B and MTP it is level with main with tokens unchanged, and opt-in
> `TF_SHARED_PRICE_LOG=1` prints each shared round's prices (#2687, refs #2605).

That is our A3 split (`TF_FLASHNEXT_DRAFT_ROW_MS`, "a stream's further rows share its experts and cost less") with the
slope **fitted** at run time per stream count and sampled flag (`shared_price.Price{plain, fixed, row}`, from plain
versus drafted residuals) instead of pasted from an environment variable. It is **not** redundant in one respect: the
new pricing runs only when `cfg.plain_guard` is on and `cfg.shared_costs` is non-empty (`shared_price.calibrate` returns
false otherwise), and Flash Next at T sets neither, so the family is still unpriced. What #2687 does replace is the
way we got there: an environment table of absolute forward milliseconds is now the wrong shape beside a mechanism
that learns the intercept and the slope, and `TF_FLASHNEXT_DRAFT_ROW_MS` competes with a measured slope that is
better evidence.

**3. What it changes at run time.** With `TF_FLASHNEXT_ROUND_MS` set (an `a+b` line or a comma list of ms by rows) and
optionally `DRAFT_ROW_MS`, a shared round's forward is priced so the core trims a round's drafts to the rows that pay,
and `observeOverhead` measures each round's time past that forward as overhead. Unset, `shared_costs` is empty and
rounds stay unpriced as before. Draft depths only; replies byte-identical (the CHANGELOG says "no reply changes").

**4. Upstream-ready?** No.
- **Measured inert.** `patches/1.2.7/README.md:144`: "**The round's price (0010's `TF_FLASHNEXT_ROUND_MS` and
  `DRAFT_ROW_MS`) is inert on this workload.** ... Priced, the engine keeps exactly the same drafts: one stream 61.18 /
  80.50 against 61.48 / 81.61 and 61.16 / 81.25 unpriced with identical counters; four streams 113.6 / 166.8 against
  113.1 / 166.7 and 112.4 / 166.3, 1,853 drafts against 1,861. A steeper line (`38+3.0`) and a flatter one (`38+1.5`)
  give the same 1,853."
- **A framework change for a family workaround:** it adds `Kind .text` to `platform/environment.zig` (absent at T),
  a `parse` branch, a `value` assert change and `readText`. That is a new environment shape, needed because Flash Next
  has no load-time timing, not because the engine wants text settings.
- Size: 13 files, +312/-61, of which two new test files (84 and 58 lines) and `cuda_round_costs.zig` (84 lines).

**5. Evidence.** The inert paragraph above, plus `README.md:232` (the three prices tried) and
`docs/CATCHUP-1.2.6.md:1092` ("A round costs 38 ms plus 3.75 ms a row on prose and 38 plus 3.85 on code").

**6. Receipt if it were revived.** A priced decode at 1, 2, 4, 6, 8 streams against unpriced, two runs an arm, plus
`TF_SHARED_PRICE_LOG=1` lines from both arms. Two windows. The counters say there is nothing to measure.

**Verdict: RETIRE** (obsolete: #2687 prices shared rounds from measurement, and ours measured inert). The live lead is
ours, not upstream's: give Flash Next `plain_guard = true` in `cuda_lanes.zig`'s lane config (with or without a cost
seed) and see whether #2687's plain-point learning engages on this family; whether a plain round ever occurs on Flash
Next is a measurement, not a claim, and it is a family change of a few lines rather than a 312-line patch.

## 0011: vision tower linears decoded at load, image rows to 16,384

**1. Applies on T?** The code applies with no conflicts; only `CHANGELOG.md` fails. The worktree pass that excluded the
CHANGELOG reported every other file clean: `docs/vision.md`, `zig/src/vision/qwen_cuda_dequant.zig` (new),
`qwen_cuda_media.zig`, `qwen_cuda_weights.zig`, `qwen_cuda_weights_logs.zig`, the two tests.

**2. Absorbed upstream?** No, and the capability is genuinely missing. T's `docs/vision.md:33` still reads "their vision
tower must use floating-point weights", and `qwen_cuda_weights.zig`'s `Reader.get` is
`r.ck.expect(..., .bf16, shape)` with no quantised arm: a ModelOpt tower's `F8_E4M3` and `U8` linears are refused by
name. Upstream does have a Flash Next CUDA vision path (`cuda_images.zig`, `cuda.kernels.qwen_vision`), so this is not
a missing path, it is a missing reader for the FP4 checkpoint's tower.

**3. What it changes at run time.** With `--vision` on `nvidia/Qwen3.8-Flash-Next-FP4-Local`, the tower's MXFP8
attention and NVFP4 MLP and merger linears are decoded to bf16 on the host at load (fp32 products, rounded once,
nearest even), so the tower runs bf16 as before; without the patch the load fails. It is not a speed lever and adds no
setting. Exactness: the decode's own tests compare every e4m3 and e8m0 byte and hand-decoded NVFP4 and MXFP8 tiles
against `core.quant` and fp64 references, and the real reader is driven through a written safetensors fixture; text
decode is untouched (`1.2.6` README: "exact; decode flat (61.7 / 82.0); not a speed lever").

**4. Upstream-ready?** Nearly. What it needs:
- **An issue and an agreed gate first**: a quantised checkpoint format read into an existing family is close enough to
  "a new model family, backend or arithmetic change" that upstream will want the gate agreed before code.
- **Split off the image-row limit raise.** `max_image_tokens` 4,096 to 16,384 (with `checkLimits`, `Plan.init` and two
  tests) is an unrelated resource-limit change: a request may now hold four 4,096-row images. That is its own PR, and
  nobody has asked for it: our recipe runs `VISION=0` and no measurement needs it.
- One behaviour left after that split: "--vision reads a ModelOpt MXFP8/NVFP4 tower". 8 files, +449/-7 including 233
  lines of new tests; no new setting, no kernel change (the dequant is host side), so no kernel contract.
- The docs change (`docs/vision.md`) is part of it and is already written in the patch.

**5. Evidence.** `patches/1.2.6/README.md:35`: "vision tower linears decoded at load, image rows up to 16,384 ... exact;
decode flat (61.7 / 82.0); not a speed lever". `docs/PARITY-CAMPAIGN-1.2.4.md:149-150` records the same gap from the port's side: "the vision tower decode is
absent (loader expects .bf16 and fails closed on a quantized tower; zero nvfp4/mxfp8 hits in `zig/src/vision`)". There is no served number, because our serve does not use it.

**6. Receipt a PR would need on T.** There is no "main" arm to compare against: main refuses the checkpoint. So the
receipt is a before and after (load error, then four 4,096-row images encoding and a described reply), plus an oracle
for the image reply on the same checkpoint. MLX already reads per-module quantized tower weights, so an MLX run of the
same image is the cheapest oracle; otherwise a torch ModelOpt dequant reference. One GPU window (image encodes only,
no decode cells), plus the host suite. On our workload the gain is zero until `VISION` is turned on.

**Verdict: SUBMIT** (rank 3), as a feature with an issue and a gate, without the 16,384 limit raise. If the owner
never intends to serve images on this model, RETIRE is equally defensible, and that is the owner's call, not a code
question.

## 0013: the window self-check logs its first differing row

**1. Applies on T?** Only after 0001 (it edits `windowCheck`, which 0001 creates); then `git apply --check` is CLEAN.
Alone it fails at `cuda_mtp_check.zig:205` because the function it edits does not exist at T.

**2. Absorbed upstream?** No (`TF_FLASHNEXT_CHECK_LOG` nowhere at T).

**3. What it changes at run time.** Nothing but a log line: on the first differing row of a failing width it prints the
first four scores from both paths, and only when `TF_FLASHNEXT_CHECK_LOG` is set in the environment. No token, no
kernel, no allocation changes.

**4. Upstream-ready?** No, for three reasons that stack. It reads `TF_FLASHNEXT_CHECK_LOG` through `std.c.getenv`, not
`platform/environment.zig`, which is a lean finding by upstream's own rule. It is a debug aid with no behaviour and no
benefit to a user, and upstream's review surface is already tight on additions of exactly this shape. And it is
meaningless without 0001, so it cannot be its own PR: it is a diagnostic branch of the check 0001 introduces.

**5. Evidence.** `patches/1.2.6/README.md:33`: "the window self-check can log its first differing row; `CHECK_LOG`
(off); log only". Nothing measured, by design.

**6. Receipt.** None is possible: no inference path is reached. **Verdict: HOLD**, meaning keep it downstream, or fold
it into 0001's PR as one branch of the check's own logging (with the setting moved into the environment table) if the
maintainer wants a diagnosable self-check. As a standalone upstream PR it is not worth the review round.

## 0018: `READOUT_FUSE`, the read-out's reduce and mix inside its products (decode)

**1. Applies on T?** Not directly, but nearly. After 0001..0007 + 0017 + 0009 the **only** conflict is
`environment.zig:66` (upstream's `TF_CACHE_EVICT` / `TF_SHARED_PRICE_LOG` neighbours). Without 0017 and 0009 it also
fails at `qmmf.zig:198` (needs 0017's `fuse_s` field for its hunk context), `cuda_knobs.zig:94` (needs 0017's
`fusedSplitN`) and `cuda_prompt.zig:152` (series coupling) and needs 0009's `qmmf_q12.zig`. So: series coupling plus
one neighbour hunk, no real drift (`git diff --stat 964174ea05 T -- zig/src/cuda/qmmf.zig` is empty).

**2. Absorbed upstream?** No. `TF_FLASHNEXT_READOUT_FUSE` is nowhere at T. Its prompt-side twin, #3413's
`TF_FLASHNEXT_READOUT_FUSED`, is **open and unmerged** (state open, `merged:false`, head `02a2b6544076`, base
`08f1de5941`), queued to land as an opt-in.

**3. What it changes at run time.** With `TF_FLASHNEXT_READOUT_FUSE=1` a decode read-out runs two launches instead of
four: the down's cluster tile carries `fn_hc_reduce_act`'s act, inject gates and 32-column sums in its epilogue, and
the up carries `fn_hc_dense_mix8`'s stream mix and its sums, so the f32 rows stop travelling through memory. Sums are
kept in the same order with `__fadd_rn`/`__fmul_rn`/`__fdiv_rn` and the up rows round to bf16 where the lane stores
them, so it is exact by construction **and by measurement**: `patches/1.2.7/README.md:391` records golden 6/6 and
every reply sha equal to the base arm's in 16 cells, and `README.md:376` the kernel table (9.938 to 9.130 ms a round,
1,649.5 to 1,420.0 launches, memory unchanged). Calls the kernels do not carry fall back to the four launches, and
prompt-shaped calls are refused by the kernels themselves (`l.usesPrompt(m, w)`), so prompt passes keep their own
path.

**4. Upstream-ready?** Not as the patch stands. What it needs:

- **It is the decode-side companion to #3413, not a duplicate.** #3413 fuses the **prompt** read-out into two new
  cluster tiles (`flashnext_hcn.cuh`, +293 lines) behind `TF_FLASHNEXT_READOUT_FUSED`, read by a 28-line
  `readout_fused.zig` and carried in `Forms.readout_fused`; its gate is `pass.hooks.prompt` plus `n >= tiles.fused_rows`.
  It does not touch `readoutNative`'s decode body. 0018 hooks exactly that body (`cuda_batch_hc.zig`'s
  `readoutNative`) for rows below the prompt tile, in the qmmf lane products. The two never contest a call.
- **Stack on #3413's branch, do not stack the patch.** 0018 does not apply on `02a2b6544`: `qmmf.cu:8`, `qmmf.zig:198`,
  `qmmf_q12.zig` missing, `cuda_batch_hc.zig:101`, `cuda_batch_kernels.zig:161`, `cuda_knobs.zig` missing,
  `cuda_prompt.zig:152`. The re-seat is concrete and small: read the setting through #3413's `readout_fused.zig`
  (`on()`) and `Forms.readout_fused` instead of our `cuda_knobs.zig` helper and its `cuda_prompt.zig` init line, drop
  the `cuda_knobs.zig` dependency entirely, and put the hook where #3413's `fuses()` now sits (it gains
  `!promptFused(...)`, which is the right guard for the decode hook too). Keep one setting: two names one letter apart
  (`READOUT_FUSE` / `READOUT_FUSED`) is a trap for users and would be the maintainer's first comment.
- **Drop the Q12 halves.** 0018 carries BF16 and 12-bit variants (`hcact`/`upmix` in `qmmf_q12.zig`, two template
  instantiations, the `?cuda.DeviceBuffer` branch in `cuda_batch_kernels.zig`). With 0009 on HOLD that is dead weight
  and a dependency on a patch that is not going up. BF16-only drops about 40 lines and two of the six kernel entry
  points.
- **Kernel contract entries are missing.** 0018 registers no contract while adding `tf_qmmf_hcact_bf16_{16,32,64}`
  and `tf_qmmf_upmix_bf16_{16,32,64}`. #3413 shows the shape and the size: `contract_flashnext_hcn.zig` (+273),
  `contract_hcn_controls.cuh` (+17), `contract_controls_set.cu` (+1), `flashnext_tile_records.zig` (+4), with two
  planted controls. 0018 needs the same: an fp64 reference for the reduce and mix ops, the accumulator and rounding
  depth, "the kernel whose bits it must equal" (the four-launch chain), launch records, and a planted control that
  fails as planted.
- **Tests.** There is no host test of the fallbacks (`hcAct`/`upMix` returning false for prompt, other row tiles,
  non-BF16); those are cheap host tests and a reviewer will ask.
- **Size:** 10 files, +368/-4 now; after dropping Q12 and adding the contract, about 330 code lines plus ~300 contract
  and test lines, 12 files. One behaviour ("a decode read-out's glue runs inside its products"), so one PR.

**5. Our evidence so far.** `patches/1.2.7/README.md:376` kernel table: `HC_Q12=1 FUSED_SPLIT=1` read-out kernels
"down 4.556 + reduce 0.724 + up 3.904 + mix 0.754 = 9.938" ms and 1,649.5 launches a round, against "down with act
4.733 + up with mix 4.303 + 0.094 at other row tiles = 9.130" and 1,420.0. Served (`README.md:391`): "Inside the cell
noise at 1, 2 and 4 streams ... and +1.8% / +1.8% at eight. The six-stream base cell (138.6 / 196.4) sits 6% under the
17-patch run of the same switches (147.7 / 210.7), so that row is not read as a gain." Memory: "The boot line's model
is 74.31 GiB with and without it from 2 to 8 streams." The "`READOUT_FUSE=1` alone" arm, whose BF16 kernels serve the
decode rows, was measured only at 1 and 4 streams (62.0 / 82.3 and 114.8 / 166.1).

**6. Receipt a PR would need on T (or on the branch after #3413 lands).**
- The kernel contract run with the planted controls (one device slot, exit status and `SUMMARY` posted).
- Decode at 1, 2, 4, 6 and 8 streams, main against the branch, **BF16 only**, two runs an arm because every cell but
  8 is inside noise: 10 boots, 20 with the repeats.
- The exactness contract at the same settings (drafted equals `"draft": false`, resumed equals fresh, concurrent
  equals solo, `tools/bench_concurrent.py --levels 1,4 --alone --serial`).
- One prompt pair (2k and 32k) to show prompt passes unchanged, since the decode hook refuses prompt calls.
- 2 GPU windows, one for the contract and one for the cells.

**On the maintainer's default-on suggestion.** It bears directly on this PR. His 2026-11-16T10:54 comment on #3413:
"Since it's exact and faster at every size we measured, making it the default looks worth a follow-up PR, with a
decode and multi-stream check alongside." 0018 **is** the decode half, and the multi-stream check is the 1 to 8
stream cells above. Two shapes are defensible:
- One follow-up: decode hook under the existing `TF_FLASHNEXT_READOUT_FUSED` row, default turned on for both prompt and
  decode, with his prompt cells plus our decode cells. This answers his note in one round and is the shape he
  described.
- Two: the decode hook under the existing setting with the default still off (smallest diff, exactness first), then a
  default flip with both sides' receipts. Safer with the noise rule, since our decode data is noise at 1 to 4.

Recommendation: the second, unless the owner wants to answer the maintainer in one PR. Either way the default flip is
the owner's and the maintainer's decision, not a code question.

**Verdict: SUBMIT** (rank 1), re-seated on `flashnext-readout-fused` after #3413 lands: one setting
(`TF_FLASHNEXT_READOUT_FUSED`), BF16 only, contract and fallback tests added. Proposed title: "Flash Next on CUDA: a
decode read-out's reduce and mix run inside its products". Branch: `flashnext-decode-readout-fused`. Patch list:
0018 with its Q12 hunks and its `cuda_knobs.zig` reader removed plus the contract work, re-cut on the landing main.

---

## What changed upstream that touches this lane

- **#2687 (2026-11-16)**: the lane core prices shared rounds itself, measured. 13 commits under `zig/src/core/lanes/`
  plus two follow-ups, `shared_price.zig` (a plain intercept and a drafted row excess, fitted from plain and drafted
  residuals, stale after 256 rounds, trials at least 64 rounds apart), `shared_round.zig` (calibration rounds,
  `TF_SHARED_PRICE_LOG`), and 70 lines of the old path removed from `engine.zig`. Gated by `plain_guard` and a non-empty `shared_costs`; Flash Next sets neither at T.
  This supersedes 0010's method and is why 0010 is RETIRE.
- **Apart from #2687, nothing else in our patched files moved**: `zig/src/cuda/qmmf.zig`,
  `zig/src/families/flashnext/cuda_prompt.zig` and `zig/src/vision/` are byte-identical to `964174ea05`, and
  0001..0007 and 0017 merged on T with three-way applies. The other upstream change that blocked hunks is the
  environment rule table: 8 new rules (`TF_CACHE_EVICT`, `TF_SHARED_PRICE_LOG`, `TENSORFOLD_LFM2_KV_PAGES`, three
  Metal switches, two slide switches), which failed the environment hunk of 0001, 0008 and 0018.
- **#3413 is open at `02a2b6544`**, queued to land as opt-in; #3218, #3475, #3477, #3523 are other lanes.

## What this triage did not establish, and must not be quoted as fact

- The boot time the 0001 self-check costs. It has never been measured; the row count (2,080 comparisons on a 96-token
  prompt) is not a time.
- 0018's BF16-only gain at 6 and 8 streams. The +1.8% at 8 streams was measured with `HC_Q12=1 FUSED_SPLIT=1` on.
- Whether Flash Next ever runs a plain shared round, which is the precondition for #2687's price to engage there.
