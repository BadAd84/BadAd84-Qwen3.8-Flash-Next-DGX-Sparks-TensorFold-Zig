# `main-1ece6e6db-r5-dev`: what this composition changes against its sources

No engine line is written here that is not in one of the sources. This file records what the composition changes in
numbering and text, which collisions it resolved, and what it does not carry.

## 1. The series and its numbering

One directory of 40 patches, applied in filename order to `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`:

| range | content | source |
|---|---|---|
| 0001-0020 | the r5 core levers | `patches/main-1ece6e6db-r5`, byte for byte apart from the comment condensing and the pin rows section 8 records |
| 0021-0022 | the INT4 port and its 17 serving-pin rows | `patches/main-1ece6e6db-r5-int4`, byte for byte apart from 0021's one quoted comment line and 0022's two quoted pin rows (section 8) |
| 0023-0024 | the KV tier's fp8 image and the append dedup | `patches/main-1ece6e6db-r5-kvtier` 0021 and 0022, byte for byte |
| 0025-0026 | the pool's cache refusal and the whole-ask budget | `patches/main-1ece6e6db-r5-kvtier-pool` 0023 and 0024, byte for byte |
| 0027-0028 | the bf16 draft-head fix and its pin row | `patches/main-1ece6e6db-r5-drafthead-bf16` 0026 and 0027, one hunk re-cut and one row regenerated |
| 0029-0032 | the int4 contract suite and the tolerance branch's three commits | PR #4183 at `d1d763ca`, and branch `int4-tolerance` commits `34274bd492`, `33f6110dc`, `3afd83b555` |
| 0033 | the merged serving pins | this package |
| 0034 | the pool test's named-slots expectation | this package (the composed gate's finding, section 6) |
| 0035 | the int4 config test's shared-width fixture | this package (the composed gate's finding, section 6) |
| 0036 | the int4 dense dispatch guard and the split-lane fixture | this package (the composed gate's finding, section 6) |
| 0037 | the split-lane fixture's second `Owned` width | this package (the full-suite gate's finding, section 6) |
| 0038 | the paged-prompt fixture's int4 and tail optionals | this package (the full-suite gate's finding, section 6) |
| 0039 | the serve-config fixture's file modes | this package (the full-suite gate's finding, section 6) |
| 0040 | the two serving-pin rows 0035 and 0036 moved | this package (regenerated from the merged bytes, section 3) |
| 0041 | the captured prompt matmul's 64-column block as a fused prompt tile, `TF_FLASHNEXT_PROMPT_KS_N`, default off | this package (the prefill-gap port; the mechanism map and the route decision are `docs/receipts/PrefillKernelPort/MECHANISM.md`) |

There is no number collision: the int4-kvtier package's `0028` (the whole-ask patch) is `0026` here, the draft-head
package's `0026`/`0027` are `0027`/`0028` here, and every appended patch has a number no other directory of this r5
family uses. The order follows the dependency the int4-kvtier package states: the INT4 pair first (the checkpoint the
tier is measured on), the tier's fp8 image, the dedup, the pool's refusal, the whole-ask budget; then the draft-head
pair, which touches `cuda_mtp.zig` after the INT4 port's line there; then the contract suite and its three tolerance
commits, which are the only patches that add the `int4-contract` verb; then the pins, last, because they hash the
merged tree; then the source-test corrections the gates forced (0034-0039); and last the pin rows those corrections
moved (0040), for the same reason 0033 is late.

`REVERTS.allow` records the series' 125 reviewed `check-patch-reverts.py` findings: 102 belong to 0001-0020 (the r5
levers re-seating their lines, with the reasons `patches/main-964174ea05/REVERTS.allow` gave them) and 23 to
0021-0039 (the INT4, KV-tier, draft-head, tolerance and gate-correction edits' own, each keyed to the document that
records it). The checker reads `125 findings, 125 allowed, 0 open, 0 stale`.

## 2. Collision 1: `zig/build/cuda.zig`'s test-step block

The draft-head package's `0026` inserts its step after `test-flashnext-part-rows-host` and expects
`test-living-host` immediately after that line. The INT4 patch had already put `test-flashnext-int4-host` in the same
place, so the source hunk stops at `zig/build/cuda.zig:275` (the draft-head package's own `RECORD.md` predicted
exactly this and named the composition as the answer).

Resolution: one block, both registrations, in the tree's order. The applied tree reads

    zig/build/cuda.zig:277  test-flashnext-part-rows-host
    zig/build/cuda.zig:278  test-flashnext-int4-host
    zig/build/cuda.zig:279  test-flashnext-draft-head-host
    zig/build/cuda.zig:280  test-living-host

0027's text was therefore re-cut: its `cuda.zig` hunk's context line is now 278's INT4 step instead of the source's
`test-living-host` line, and the inserted line is byte-identical to the draft-head package's. Nothing else in 0027
differs.

## 3. Collision 2: `zig/tests/fixtures/gradient-serving.tsv`

Two sources re-pin rows of the same fixture:

- the INT4 package's `0022` (here `0022`) re-pins 17 rows from the tree after the INT4 port, the `cuda_mtp.zig` row
  included (`2f7273781b97c2f1ceb9a7ecac6104c0e9934b7c8afb2b6ab6e5d7d8782053f5`);
- the draft-head package's `0027` (here `0028`) re-pins the same `cuda_mtp.zig` row from the tree after both the INT4
  port and the draft-head fix.

Both values were generated on a different tree than the merged one, so neither is right here. The pins were
regenerated from the merged bytes once, after every code patch applied, with `work/DevComposition/repin.py`: every row
of this fixture is mode `raw`, so a row's value is the sha256 of the file's bytes, the same rule
`zig/tests/gradient_serving_pin.zig` applies to a raw row. No row was hand-edited. Two rows moved in the merged tree:

| row | line | before | merged |
|---|---|---:|---:|
| `zig/src/families/flashnext/cuda_mtp.zig` | 145 | `2f727378...` (INT4 pin, draft-head code missing) | `304a8cfc153fb4cd30743d1c996e8f54501f219a0718bcf9b896ca4c5916bf2a` |
| `zig/src/cuda/root.zig` | 109 | `6f28589a...` (INT4 pin, contract export missing) | `167d76c511f03e5ce78747066a1243dd187ecd6c6731fdd62f406f0f60c4d93b` |

`0028` carries the first row and 0033 the second, so the draft-head package's pin patch still exists as its own patch
and the suite's row lands after the suite. Every other row of the 170 is unchanged, because no other patch moves a
pinned file (the INT4 package's own 17 rows still hold; `zig/src/cuda/kernels.zig` was already pinned for the INT4
registration).

Two of the corrections made after that gate move pinned files of their own, and the 34-patch gate's pin check ran
before either existed: 0035 edits `cuda_config.zig` and 0036 edits `cuda_batch.zig`. `test-gradient-serving` fails on
both rows until they are regenerated, which the 39-patch run observed (its pin check read `files 170 failing 2`, then
the pin test named `cuda_batch.zig`). 0040 regenerates them from the merged bytes with the same `repin.py` and rule:

| row | before | after |
|---|---|---|
| `zig/src/families/flashnext/cuda_batch.zig` | `6e8e7a161db369cdeb2bda2544dea2b1614f93b7bf4070044b16dc618f21659a` (the tree before 0036) | `a1b14b6cfb832481a6d2d399ca792c0f14b221df6ffab010bb8d90ed196a986b` |
| `zig/src/families/flashnext/cuda_config.zig` | `598d1276723c7094aaea615751f609ff9488d409a90660c4710cf04f40db04a9` (the tree before 0035) | `b512b6ccb57047d8de8eb00f3b86805c79be6208c250d5da36fe53be7845c0ca` |

After 0040 the pin check reads `files 170 failing 0` and `test-gradient-serving` passes; no other row moved.

0041 edits three pinned serving files (`qmmf.cu`, `qmmf.zig`, `cuda_prompt.zig`), so it carries their regenerated
rows in the same patch, by the same rule (mode `raw`, the file's bytes):

| row | before | after |
|---|---|---|
| `zig/kernels/cuda/qmmf.cu` | `5c55f08fdd951f683159dbaf5b3c655aa956cc15c82c4476f07270215101d1f4` | `2d11c47c9d9c90c3b306bd6b0218621f29ad71e82fb7195ced89a2014b141e46` |
| `zig/src/cuda/qmmf.zig` | `cb04b89dae52c23327d8a258d2d5d0b23782d7ac271e38e117637d251e344ff2` | `53ed6ec786b41240ea1ec0d8a2e7696fe89dc145d8d9b067661012857c8cfa98` |
| `zig/src/families/flashnext/cuda_prompt.zig` | `2c1a5c86a8891e1d6066454dc2caa5c5aa8a7c60d4bdad439d907514ece2ff07` | `616027f8e03ce33a5cc249f915608b50ca156d772599c2e20ef703685aee96a8` |

After 0041 the pin check reads `files 170 failing 0`. `zig/src/families/flashnext/cuda_knobs.zig` is not pinned (no
row of its own today), so the two new settings' reader is not in the fixture; the rows that ARE pinned are regenerated.

## 4. The int4 contract suite: the carrier the tolerance commits need

The tolerance branch was cut on `d1d763ca`, the live head of PR #4183, and its three commits modify
`zig/tests/cuda/contract_int4.zig`, `zig/tests/cuda/int4_ref.zig`, `zig/kernels/cuda/contract_int4_controls.cuh`,
`zig/build/kernel_contract.zig`, `zig/tests/cuda/main.zig`, `zig/tests/cuda/main_usage.zig`, `docs/kernel-contract.md`
and add `zig/tests/cuda/int4_controls.zig` and `docs/int4-contract-allowances.md`. None of those files existed in this
composition: its INT4 route is production's lifted `fn_int4.cu` with `zig/src/families/flashnext/cuda_int4.zig`, not
#4183's `zig/src/cuda/int4.zig`, and it carried no contract suite at all (the int4 package's README says so
explicitly: "no contract records, no planted controls, no float64 device test").

So the port carries the suite as well: `0029` imports PR #4183's contract slice at `d1d763ca` (the tolerance branch's
parent, before the three commits), and `0030`, `0031`, `0032` are the branch's three commits in order. This is the
only way the tolerance work can run here: its allowance model, controls, gate-4 margin and verb are all edits to that
suite, and the alternative (importing the changed files alone) would have left dead code and a verb with no suite
behind it.

The suite is carried because the kernel it tests is the composition's kernel: `zig/kernels/cuda/fn_int4.cu` here
defines every groups-of-128 instantiation the suite resolves, with the same mangled symbols
(`_ZN10tf_fn_int411int4_kernel...`, `_ZN10tf_fn_int418int4_prompt_kernel...`); the two `fn_int4.cu` files differ only
in the groups-of-64 instantiations this engine adds for a two-rank serve, one `ld_nc2` local load, comments and the
instantiation list. The record tables the suite needs (`int4_records.zig`, `pending_133.zig`, `registry_joins.zig`)
and the controls image's include are carried with it.

Adapted, because this base is not the PR's:

| file | adaptation |
|---|---|
| `zig/src/cuda/root.zig` | the export is inserted after `experts`; this base has no `pair_experts`/`affine_experts`/`roce_pair_rule` neighbours. The test import applied as written |
| `zig/kernels/cuda/contract_controls_set.cu` | the include is appended after `contract_hcn_controls.cuh`; this base has no `contract_qwen3_asr_controls.cuh` line |
| `zig/tests/cuda/contract_limits.zig` | the `fn_int4` lookup is placed after `fp8_experts`; this base's image list differs |
| `THIRD_PARTY_NOTICES.md` | the notice states that this tree also builds the groups-of-64 instantiations, and names both host packers (`cuda_int4.zig` and `cuda/int4.zig`), instead of claiming the groups-of-64 are not built |

Not carried from the PR slice: `zig/kernels/cuda/fn_int4.cu` (the composition's own, from 0021),
`zig/src/cuda/kernels.zig` and `zig/build/cuda_kernels.zig` (0021 already registers the image),
`zig/src/core/lanes/depth.zig` and `depth_test.zig` (PR housekeeping unrelated to the contract and already carrying
this series' 0010), the `CHANGELOG.md` deletions and `RUNBOOK.md` (PR housekeeping), and the fixture rows (regenerated
in 0033 by the rule in section 3).

## 5. Identity of the copied text

0001-0020 are copies of `patches/main-1ece6e6db-r5` (verified by `sha256sum` against that package's `SHA256SUMS`),
with two classes of edit section 8 records: ten patches' comments condensed to one line each (0003, 0005, 0008, 0013,
0014, 0015, 0017, 0018, 0019 and 0034) and five pin rows in 0020 regenerated from the fixed bytes. 0023-0026 are
byte-identical to their sources; 0021 and 0022 carry only the quoted lines section 8 names:

| patch | sha256 | source |
|---|---|---|
| 0021-int4-autoround | `9ac1a2c781ca8fd105dba91fcb94a70da8d32101b23d7974c62ecef7401ddba2` | r5-int4/0021, one quoted comment line follows 0018 (section 8) |
| 0022-int4-serving-pins | `7aed83e75e261249c3135cf9c89cd1ca6e92fee6bd70c40f5a10a219ee3a6907` | r5-int4/0022, two quoted pin rows follow 0020 (section 8) |
| 0023-kv-tier-fp8 | `47d90e3b5f71cd9a0404bb6f1ce836e09f709ebea44851308e8440e65d479dc7` | r5-kvtier/0021 |
| 0024-kv-tier-dedup | `cd5a336200f7c218fa53e52fdc11d51f2ee2b34a4010fcb4dda297e15ebda864` | r5-kvtier/0022 |
| 0025-kv-tier-pool | `e6a4872ed53041d3e5e4b850a3733dadba764b15c54941420bd4b480a9032589` | r5-kvtier-pool/0023 |
| 0026-kv-tier-full-ask | `cfec2bb31c847fed1523812639125b6a6267ceee4e85970d1918f513768272db` | r5-kvtier-pool/0024 |

0027 is the draft-head package's `0026` with the one context line named in section 2 changed
(`d06790b2a3075cfecf756f128fcb15b2df29fb7b709df3f8b631e006d3222046`). 0028 is that package's `0027` with the row
value from section 3, and one quoted `cuda_mtp_check.zig` row follows section 8's value
(`a0606c1a680861e1165373288dc5fc98259faf7b711f5ad32b732b6270215559`). 0029-0034 are constructed here (0033's quoted
`qmmf.zig` row is section 8's); the source shas and the suite's own identity are in `RECORD.md`.

The applied-result identity, measured in the lean pass's gate (section 8, `~/work/LeanDebt/out/gate40.log`): applying
the 40 patches in order to a pristine worktree at `1ece6e6d` yields a tree whose manifest (`find` + `LC_ALL=C sort -z`
+ `sha256sum` over the tree) is `9e3c2276cbf297d71e3d5b072f801ae18b2309f8b213e9754b8cac3aa1c359e4`, and
`git diff --check` reads nothing. `RECORD.md` has the line and the run.

## 6. The gates' corrections: 0034-0039, and the pin rows they moved (0040)

The full `test-cuda-host` on the composition exposed six fixture defects and one engine line in the int4 port's wake.
0034, 0035, 0037, 0038 and 0039 are test corrections and change no engine line; 0036 narrows one dispatch guard in
`cuda_batch.zig` so a view with no kernel group keeps the normal lane, and sets the split test's `shared_width`.

- **0034, the pool package's named-slots test.** `cuda_cache_capacity_test.zig`'s `named8` arm expected an asked
  `--prompt-cache-gib 6` beside a named `TF_KV_SHARE` of 8 to leave `6 GiB - 8 x 115,642,368` as *copied rows*. That
  contradicts the behaviour `kv_pool_band_test.zig` pins from receipt #2987: a named TF_KV_SHARE keeps the cache's
  remainder as *pages* (`kept`), and the copied rows are 0. The engine is right in both; the full-ask test's last arm
  was wrong. It now reads `named8.copied == 0` and `named8.kept == 6 GiB - 8 slots`, and the step reads
  `22/22 tests passed`.
- **0035, the int4 config test.** `cuda_config.zig`'s wider-shared-expert test set the fixture to `wt.moe_w + 64` and
  expected the learned-neuron allowance of 64 to admit it. The int4 port splits the shared expert's width from the
  routed experts' (`wt.shared_w` is 1,280 while `wt.moe_w` is 640), and `mismatch` compares against `wt.shared_w`; the
  fixture now starts from `wt.shared_w + 64`, which is the value the check reads.

Both were found by the composed gate, not by any source package's own gate: each source gate ran a filtered step or a
tree without the other patch, and this is the first tree where the full suite runs them together. Before 0034 the gate
read `21 pass, 1 fail (22 total)`; after it, `22/22`. 0035's evidence is the full-suite run in `RECORD.md` (its test
fails before the change with `expected null, found { ... "shared_expert_intermediate_size" }`).

0036 is the same class for the run's other two findings. `cuda_batch.lane` routed every `Q4` carrying an int4 view to
`cuda_int4.dense`, whose group switch returns `error.Invalid` for a fixture with no 64/128 group; the dispatch is now
narrowed to those two groups, so a matrix in another group keeps the normal lane. That guard is the one engine line
these corrections touch. The split-lane test built `Owned` from `undefined` and never set `shared_width`, the field the
int4 port reads; it now sets `wt.moe_w`.

The 39-patch run left three failures, and each was a fixture that predates the int4 port's fields rather than a
behaviour the port should change:

- **0037, the split test's second `Owned`.** The test builds `Owned` from `undefined` twice: once in the loop 0036
  fixed, and once in the trailing arm that breaks the strided down launch's eligibility. The second fixture still left
  `shared_width` undefined, so `cuda_batch_side.down` passed a garbage stride to `qmmf.matmulOut`, whose
  `@as(i32, @intCast(if (m == 1) w.k else ldx))` aborted with `integer does not fit in destination type`
  (`qmmf.zig:368`, from `cuda_split_lane_test.zig:341`). It now sets `wt.moe_w`, the same value the loop's non-split
  arm uses and the only width that arm's weight has.
- **0038, the paged-prompt fixture's optionals.** `cuda_paging_batch_test.zig` builds `var lw: Layer = undefined` and
  sets only the fields its attention route needs; the two projections `cuda_batch.lane` reads then carried undefined
  `int4` and `tail` tags. Before 0036 the undefined `int4` took the lane into `cuda_int4.dense` with an unsupported
  group (the 35-patch run's `cuda_paging_batch_test.zig:176`); with the guard in place the undefined `tail` took it to
  the BF16-tail launch with `part == 0`, which `matmulOut` refuses with `MissingLanePart`. Both projections now state
  `int4 = null` and `tail = null`, which is what the fixture meant: a block-FP8-free, int4-free layer.
- **0039, the serve-config fixture's file modes.** `cli_config_test.zig` wrote `serve.toml` and `big.toml` with
  `writeFile` and relied on the process umask for their mode. On this host the umask is 002, so the files land 0664
  and `cli_config.expand`'s group-write guard refuses them, correctly, before the test reaches the behaviour it
  measures (the mode cases further down chmod explicitly and were never affected). The fixture now chmods both files
  to 0644 itself; the guard is untouched. A gate run under `umask 022` never saw this, which is why the earlier gate
  log did not carry it.

0035 and 0036 edit two files the serving-pin fixture pins (`cuda_config.zig`, `cuda_batch.zig`), and the 34-patch gate
ran its pin check before either existed; `test-gradient-serving` fails on the stale rows. 0040 is those two rows,
regenerated from the merged bytes with `work/DevComposition/repin.py` and never hand-edited (section 3).

## 7. What the composition does not change

- The four settings 0021 reads through `zig/src/platform/environment.zig` are the INT4 package's own rows, and the dev
  env files state them now, with their read sites (`README.md`, "The serve shape, and the env and launcher that carry
  it"); the coverage gate reads `99 settings in scope, set 99, missing 0`. 0041 adds two settings of its own
  (`TF_FLASHNEXT_PROMPT_KS_N`, `TF_FLASHNEXT_PROMPT_KS_GROUP`), read through `cuda_knobs.zig` like the family's other
  `TF_FLASHNEXT_*` switches; both are default-off, so the composition's served behaviour without them is unchanged.
- The INT4 package's gap against issue #3368's six steps is unchanged, including the MTP layer recoded to block FP8 at
  load (drafts only, replies exact) and the missing float64 fidelity cells.
- The tier's missing pieces are unchanged: the staging ring, a store pin and block-name lineage.
- Nothing of PR #4183's kernel implementation (`zig/src/cuda/int4.zig` as the serving route) is adopted: `int4.zig`
  here exists for the contract suite, and the serve still uses `zig/src/families/flashnext/cuda_int4.zig`.

## 8. The lean pass: 44 comment findings cleared, 19 findings left with their reasons

The lean pair run as upstream's CI runs it (each side its own copy of the tree and of `tools/zig/lean_check.py`, the
pristine base against the head through the head's `lean_new.py`) read `lean: 231 problems, 168 on the base, 63 new`
on the composition as first assembled. This pass removes every finding of the comment class and leaves the 19 that
cannot be fixed without changing code. It changes no engine line: the whole diff from the pre-pass tree is the 32
comment blocks' lines (44 instances in 20 files: 29 added, 65 removed) and the five serving-pin rows below, and
`git diff --check` reads nothing.

**The comment class: 44 instances, 32 blocks, 20 files, 10 patches.** A block is a run of consecutive `//`, `///` or
`//!` lines, or a single comment line past 120 columns; every block is now one line of at most 120 columns, through
the patch that owns the text:

| patch | blocks | instances | where |
|---|---|---|---|
| 0003 | 2 | 7 | `flashnext_kv8_pending.zig`'s 7-line header; `cuda_snap.zig`'s test comment |
| 0005 | 1 | 1 | `cuda_knobs.zig`'s 2-line header |
| 0008 | 3 | 6 | `cuda_part_rows_test.zig`'s 5-line header; two `cuda_scratch_sizes.zig` blocks |
| 0013 | 1 | 1 | `cuda_mtp_check.zig`'s 2-line diagnostics comment |
| 0014 | 1 | 4 | `cuda_mtp_mxfp8.zig`'s 5-line header |
| 0015 | 7 | 7 | `flashnext_kv8.cuh` (one long line, one 2-line block), `cuda_batch_lanes.zig`, `cuda_kv_lanes.zig`, `cuda_lanes_load.zig` (one long line each), `cuda_pages.zig` (header, one doc line) |
| 0017 | 3 | 3 | the fused split's 2-line blocks in `qmmf.cu`, `qmmf.zig`, `cuda_knobs.zig` |
| 0018 | 12 | 13 | the read-out fuse's comments in `qmmf.cu` (three blocks, one of 3 lines), `qmmf_body.cuh`, `qmmf.zig` (three), `qmmf_q12.zig`, `cuda_batch_hc.zig`, `cuda_batch_kernels.zig` (two), `cuda_knobs.zig` |
| 0019 | 1 | 1 | `contract_lane_half.zig`'s added second header line |
| 0034 | 1 | 1 | `cuda_cache_capacity_test.zig`'s 2-line comment above `named8` |

`0021` quotes one of 0018's condensed lines as context and follows it (one line); no other patch text changes. The
comment fixes move five pinned files' bytes, so `0020` carries their regenerated rows (§5) and `0022`, `0028` and
`0033` follow the same rows where they quote them as context:

| row | before | after |
|---|---|---|
| `zig/kernels/cuda/qmmf.cu` | `777f7c01facf9b00b925fd7de4fe73c4663eb1d7aea6c342726df9192133b2a4` | `5c55f08fdd951f683159dbaf5b3c655aa956cc15c82c4476f07270215101d1f4` |
| `zig/src/cuda/qmmf.zig` | `0a88f17ab543e3b98460b2687cd507024085403af4d57c3494c1febc354ab258` | `cb04b89dae52c23327d8a258d2d5d0b23782d7ac271e38e117637d251e344ff2` |
| `zig/src/families/flashnext/cuda_lanes_load.zig` | `18b19ecce27f3e8701caee5ba531ac79ed24399b5e0d870328c5a29d9e417e5a` | `473a725be4928d310d13677dee2742a230a92dc02a204c8b8f7eec85cdf11f62` |
| `zig/src/families/flashnext/cuda_mtp_check.zig` | `fb426202a42133aacb5ae6bd192cf2e3917025eecf2c58634129096326bcbe84` | `41687d959488276d2bde2cc9dd764b8a06fcbf3dd980be903fed02654d5a6cb5` |
| `zig/src/families/flashnext/cuda_snap.zig` | `b9606c5abce71c3f94b5b698152c7d74a453c79cd5d42e1c4dfdb9101112ea30` | `fc89ce6e3743fdcddac14c6d81a806aed17fdfdc1c105eca40e4b06d9faed9f4` |

**The 19 left untouched, and why each is not behaviour-free.** Thirteen are files over 600 lines. The rule's fix is
splitting the file into modules - new imports, moved declarations and re-exports - which is a code-structure change,
not a comment, dead-code or formatting edit, so it is not made here (and a comment trim cannot pay for it: these files
add 2 to 344 lines against their base, of which 0 to 16 are comments):

| file | base -> head lines |
|---|---|
| `zig/kernels/cuda/qmmf.cu` | 293 -> 633 |
| `zig/src/core/lane_host.zig` | 600 -> 602 |
| `zig/src/core/lanes/depth.zig` | 594 -> 603 |
| `zig/src/core/lanes/stream.zig` | 600 -> 602 |
| `zig/src/core/lanes/windows.zig` | 575 -> 640 |
| `zig/src/cuda/qmmf.zig` | 576 -> 717 |
| `zig/src/families/flashnext/cuda_batch.zig` | 592 -> 626 |
| `zig/src/families/flashnext/cuda_glue.zig` | 563 -> 626 |
| `zig/src/families/flashnext/cuda_lanes.zig` | 600 -> 606 |
| `zig/src/families/flashnext/cuda_ple.zig` | 588 -> 636 |
| `zig/src/families/flashnext/cuda_prompt.zig` | 582 -> 610 |
| `zig/src/families/flashnext/cuda_prompt_wt.zig` | 594 -> 610 |
| `zig/tests/cuda/contract_tests.zig` | 600 -> 606 |

Six are settings read by a raw `std.c.getenv`. Reading them through `platform/environment.zig` adds table rows and
changes the read sites, and the table's reader is what parses the text and refuses a malformed value: that is code
behaviour, and it adds settings the engine's table does not have, so it is not done here (the switches themselves and
their env rows are already the patches' own; `docs/ENV-REGISTER.md` records the values):

| site | finding |
|---|---|
| `zig/src/families/flashnext/cuda_hc_q12.zig:17` | direct getenv of `TF_FLASHNEXT_HC_Q12` |
| `zig/src/families/flashnext/cuda_mtp_check.zig:212` | direct getenv of `TF_FLASHNEXT_CHECK_LOG` |
| `zig/src/families/flashnext/cuda_mtp_mxfp8.zig:19` | direct getenv of `TF_FLASHNEXT_MTP_WEIGHTS` |
| `zig/src/native/cuda_startup_phase.zig:14` | getenv of a name that is not a literal (the `flag`/`copyPolicy` wrappers) |
| `zig/src/native/cuda_startup_phase.zig:23` | direct getenv of `TENSORFOLD_COPY_MISS` |
| `zig/src/native/cuda_startup_phase.zig:27` | direct getenv of `TENSORFOLD_COPY_RAMP` |

The pair on the fixed tree reads `lean: 187 problems, 168 on the base, 19 new`: the 19 above, and no comment finding.
The gate (`RECORD.md`, Checks) reruns apply, fmt, pincheck, the host suites, the lean pair and `check-patch-reverts`
on this package.

