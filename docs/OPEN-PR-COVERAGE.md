# Our pull requests against upstream `ashhart/TensorFold`

Read on 2026-11-23 with `gh pr view` and `gh api repos/ashhart/TensorFold/commits/<sha>` for each landing commit;
the shas and dates are those reads'. A "landed" sha is the commit on main whose message names the pull request.

## Merged

| PR | what it carries | merged | landed |
|---|---|---|---|
| #3611 | `core/quant`: a GPTQ reader for AutoGPTQ v1 group-128 symmetric weights | 2026-11-19 | code `51a108030`, changelog `0f8e35a1a` |
| #3726 | Flash Next on CUDA: a prompt pass holds 3,072 rows | 2026-11-19 | code `e172bcc29`, changelog `bc99bab7b` |
| #3413 | Flash Next: `TF_FLASHNEXT_READOUT_FUSED`, a prompt pass's BF16 read-out on two fused tiles | 2026-11-20 | code `12233bee5`, changelog `9748adc7e` |
| #3727 | Qwen3.5/3.8 and Flash Next on CUDA: `--vision` reads a quantized ModelOpt tower | 2026-11-20 | code `174cfff34`, changelog `e0ebc7b69` |
| #2044 | glm cuda: decode windows' EXL3 experts run on the 16-pair item plan | 2026-11-20 | `82e8927f9` |
| #3477 | Flash Next: the draft head's rows are affine4 unless `TF_FLASHNEXT_DRAFT_HEAD=bf16` | 2026-11-21 | code `230837886`, changelog `50b819756` |
| #4009 | Flash Next: one pooled n-gram gather for every row a shared pass needs | 2026-11-21 | `69e4d0f04` |
| #3475 | Flash Next: `TF_FLASHNEXT_FUSED_SPLIT` runs wide split-K decode calls on the fused form | 2026-11-21 | `308d5e1fd` |

Each absorbed lever is retired from our series at the next re-seat; `patches/main-1ece6e6db-r5/RETIRED.md` carries the
hunk-level record and the instruction, so nothing is re-added.

## Open

| PR | what it carries | state at 2026-11-23 |
|---|---|---|
| #4075 `flashnext-copy-window-up` | a lone stream's copy window takes the width the boot check proves | clean and mergeable (head `4e7bc21d9`, 26 files, +882 / -109), awaiting upstream's GB10 check; nothing needed from us |
| #3218 `flashnext-mtp-weights` | `TF_FLASHNEXT_MTP_WEIGHTS` selects how the drafter keeps its BF16 linears | head `20003e9670`; nothing further needed from us, and upstream settles the `CHANGELOG.md` hunk at landing (the maintainer, 2026-11-19); upstream's device check is the open item |
| #3523 `flashnext-config-widths` | config-driven top-k and shared expert width | head `37d99a8a`, awaiting upstream's GB10 check; its landing route is recorded: the only overlaps are `CHANGELOG.md` and `zig/tests/fixtures/gradient-serving.tsv`, both reconciled in a scratch merge against the main it was cut on, so landing is a fixture refresh and not a source conflict |
| #4183 `cuda-int4-kernel-m` | an int4 W4A16 kernel for GPTQ group-128 routed experts and the LM head | head `5aced6d3e8`, 20 files, +2,018 / -3; the maintainer's four asks are answered (rebase and re-pin, the prompt-down BF16 gates, the BF16 dense wrapper, a real `int4-contract` dispatch) and the **device summary is outstanding**; full state in `docs/INT4-PORT.md` |
| #4449 `flashnext-block-fp8-projections-up2` | block-FP8 projections load on the FP8G lane | draft (head `42ff781a5`, 33 files, +931 / -105), stacked on its parent #3523 and awaiting that PR's landing |

#3218 and #3523 have moved under upstream's main since their heads were refreshed, so GitHub reads both as
conflicting; neither needs a change from us before its device check, and a rebase is due at landing.

## The part fix, not yet opened

The MTP head's `fc_h` lane sizing fix (`work/PartFix/REBASE.md`): head `bbbf0d414b5ef05fd291812da2f8d49f0932998e`
on `1c9688ca2`, one signed commit, 2 files, +133 / -2, host gates green, issue text and pull request text approved.
It is re-seated and posted after the device gate; the issue is not opened yet.

## Our series

Our levers are 20 patches on upstream main `1ece6e6db` (`patches/main-1ece6e6db-r5`), with
`patches/main-1ece6e6db-r5-int4` (production's INT4-AutoRound checkpoint) and `patches/main-1ece6e6db-r5-kvtier` (the
NVMe KV tier) on top. The 13-patch series cut against v1.2.6 (`patches/1.2.6`) and the 19-patch series cut against
v1.2.7 (`patches/1.2.7`) carry the same levers on their own bases.

The recipe's 17 patches (`docs/RECIPE-PATCHES-VS-UPSTREAM.md`) are a porting backlog for the recipe's own 1.1.4 line
only: our levers are the series above plus the eight merged pull requests and the four open ones in the tables. The
recipe's features are not part of that series.
