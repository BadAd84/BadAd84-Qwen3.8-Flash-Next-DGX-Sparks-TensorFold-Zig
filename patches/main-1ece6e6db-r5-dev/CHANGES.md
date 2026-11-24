# `main-1ece6e6db-r5-dev`: what this composition changes against its sources

No engine line is written here that is not in one of the sources. This file records what the composition changes in
numbering and text, which collisions it resolved, and what it does not carry.

## 1. The series and its numbering

One directory of 35 patches, applied in filename order to `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`:

| range | content | source |
|---|---|---|
| 0001-0020 | the r5 core levers | `patches/main-1ece6e6db-r5`, byte for byte |
| 0021-0022 | the INT4 port and its 17 serving-pin rows | `patches/main-1ece6e6db-r5-int4`, byte for byte |
| 0023-0024 | the KV tier's fp8 image and the append dedup | `patches/main-1ece6e6db-r5-kvtier` 0021 and 0022, byte for byte |
| 0025-0026 | the pool's cache refusal and the whole-ask budget | `patches/main-1ece6e6db-r5-kvtier-pool` 0023 and 0024, byte for byte |
| 0027-0028 | the bf16 draft-head fix and its pin row | `patches/main-1ece6e6db-r5-drafthead-bf16` 0026 and 0027, one hunk re-cut and one row regenerated |
| 0029-0032 | the int4 contract suite and the tolerance branch's three commits | PR #4183 at `d1d763ca`, and branch `int4-tolerance` commits `34274bd492`, `33f6110dc`, `3afd83b555` |
| 0033 | the merged serving pins | this package |
| 0034 | the pool test's named-slots expectation | this package (the composed gate's finding, section 6) |
| 0035 | the int4 config test's shared-width fixture | this package (the composed gate's finding, section 6) |

There is no number collision: the int4-kvtier package's `0028` (the whole-ask patch) is `0026` here, the draft-head
package's `0026`/`0027` are `0027`/`0028` here, and every appended patch has a number no other directory of this r5
family uses. The order follows the dependency the int4-kvtier package states: the INT4 pair first (the checkpoint the
tier is measured on), the tier's fp8 image, the dedup, the pool's refusal, the whole-ask budget; then the draft-head
pair, which touches `cuda_mtp.zig` after the INT4 port's line there; then the contract suite and its three tolerance
commits, which are the only patches that add the `int4-contract` verb; then the pins, last, because they hash the
merged tree; then the two source-test corrections the composed gate forced (0034, 0035).

`REVERTS.allow` records the series' 125 reviewed `check-patch-reverts.py` findings: 88 keep the reason
`patches/main-964174ea05/REVERTS.allow` gave them (the r5 levers re-seat those lines), and 36 are the INT4, KV-tier,
draft-head and tolerance ports' own edits, each keyed to the document that records it. The checker reads
`125 findings, 125 allowed, 0 open, 0 stale`.

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

0001-0020 are byte-identical to `patches/main-1ece6e6db-r5` (verified by `sha256sum` against that package's
`SHA256SUMS`). 0021-0026 are byte-identical to their sources:

| patch | sha256 | source |
|---|---|---|
| 0021-int4-autoround | `3cffe99044c6ffd14820a8bc88085cc6e18990bddb5a5ab90d57223de4dda1a1` | r5-int4/0021 |
| 0022-int4-serving-pins | `18ab81216fa104ea1853f27b60ccf9e88355ed7dde2aa976ff7d08b06bf11c26` | r5-int4/0022 |
| 0023-kv-tier-fp8 | `47d90e3b5f71cd9a0404bb6f1ce836e09f709ebea44851308e8440e65d479dc7` | r5-kvtier/0021 |
| 0024-kv-tier-dedup | `cd5a336200f7c218fa53e52fdc11d51f2ee2b34a4010fcb4dda297e15ebda864` | r5-kvtier/0022 |
| 0025-kv-tier-pool | `e6a4872ed53041d3e5e4b850a3733dadba764b15c54941420bd4b480a9032589` | r5-kvtier-pool/0023 |
| 0026-kv-tier-full-ask | `cfec2bb31c847fed1523812639125b6a6267ceee4e85970d1918f513768272db` | r5-kvtier-pool/0024 |

0027 is the draft-head package's `0026` with the one context line named in section 2 changed
(`d06790b2a3075cfecf756f128fcb15b2df29fb7b709df3f8b631e006d3222046`). 0028 is that package's `0027` with the row
value from section 3 (`1ad421280fa1090549d5150209241b99c5678e6721c2c71c33b811577bea117c`). 0029-0034 are constructed
here; the source shas and the suite's own identity are in `RECORD.md`.

The applied-result identity, measured: applying the 35 patches in order to a fresh worktree at `1ece6e6d` reproduces
the gated tree file for file (the manifest comparison reads one difference, the worktree's `.git` pointer, and
nothing else). `RECORD.md` has the manifest hash and the gate run.

## 6. The composed gate's two test-expectation fixes: 0034 and 0035

The full `test-cuda-host` on the composition exposed two source tests whose fixtures encode a tree the composition is
not. Neither is an engine defect, and neither patch changes an engine line.

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

## 7. What the composition does not change

- No setting is added: the four settings 0021 reads through `zig/src/platform/environment.zig` are the INT4 package's,
  and `scripts/qwen38/zig/target/env/dev.env` does not yet state them (README, "The serve shape").
- The INT4 package's gap against issue #3368's six steps is unchanged, including the MTP layer recoded to block FP8 at
  load (drafts only, replies exact) and the missing float64 fidelity cells.
- The tier's missing pieces are unchanged: the staging ring, a store pin and block-name lineage.
- Nothing of PR #4183's kernel implementation (`zig/src/cuda/int4.zig` as the serving route) is adopted: `int4.zig`
  here exists for the contract suite, and the serve still uses `zig/src/families/flashnext/cuda_int4.zig`.
