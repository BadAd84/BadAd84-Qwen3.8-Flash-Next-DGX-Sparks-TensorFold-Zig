# Re-seat classification against upstream main `d7c969c64` (2026-11-19)

Classification only: no build, no test, no GPU window, no patch file edited, nothing pushed. The series under test is
`patches/main-964174ea05`, the accepted series (19 patches). `patches/main-964174ea05-int4` is the experimental INT4
series and is out of scope; so is PR #3523 (config widths), which carries no patch of this series.

- Upstream `ashhart/TensorFold` main at the start: **`d7c969c649cec5e85a0e0b964c863cfb97172e30`**, read from
  `git -C work/upmain rev-parse origin/main` after `git fetch origin main`; dated 2026-11-19 14:24:30 +0000, subject
  "changelog: #3774 under Unreleased".
- The series' own base: `964174ea05879e6dde1de1198a3aae3ef8b46a3b` (2026-11-15, `v1.2.9-33-g964174ea05`).
- 755 commits between the two (`git log --oneline 964174ea05..d7c969c64 | wc -l`).
- On the levers' own surface (`zig/src/families/flashnext`, `zig/kernels/cuda`): 59 files, +2,956/-765. Adding the
  other surface the patches touch (`zig/src/platform/environment.zig`, `environment_test.zig`, `zig/src/core/lanes`):
  69 commits.

## Result

| verdict | patches |
|---|---|
| applies to `d7c969c64` as cut | 0019 |
| re-seat needed; nothing upstream absorbed it | 0001 to 0018 |
| absorbed by upstream, retire | none |

Nothing is retired here. No patch's added code is on main: every lever's distinctive identifier is absent (table 3),
every file the patches create is absent, and the only keyword-bearing added lines found on main are upstream's own
pre-existing code (table 3's note). The 18 failures are two separate things, recorded per patch: upstream moved the
same lines for unrelated work (table 2, "drift", with the commit), or the hunk needs context an earlier patch of the
series adds (table 2, "depends on", with the patch).

## 1. Upstream state and recommended action, one row a patch

| patch | lever | upstream state (2026-11-19) | applies | action |
|---|---|---|---|---|
| 0001 | a lone stream's copy window grows to the boot self-check's largest row-exact width; a log-carrying verify window takes the row-by-row DeltaNet | no PR; fork branches `flashnext-copy-window-up` (`d8c4dd5a80c1`) and `window-48-rows` (`93475cf7e26d`), both unopened | no | re-seat; compare with the newer branch cut before carrying |
| 0002 | copy re-sync past an edit, the copy ramp and the miss rules | no PR, no branch | no | re-seat (one 3-line context drift) |
| 0003 | `--kv-cache fp8` for Flash Next (e4m3 rows, a scale a row) | no PR, no branch | no | re-seat |
| 0004 | n-gram rows through a direct-mapped row cache, parked readers, draft-ahead, one gather a shared pass | no PR; fork branch `flashnext-gather-early-up` (`9d60e51db10c`) carries the gather-early sub-lever only | no | re-seat; keep as local patch |
| 0005 | prompt passes drain less, 3,072-row chunks, the relaxed MX128 prompt tile | PR #3726 OPEN, head `ad1f67797691`, covers the 3,072-row chunk only | no | re-seat; split before any upstream upload (MX128 not in the PR) |
| 0006 | the MX128 tile in two stages, two blocks an SM | no PR, no branch | no | re-seat after 0005 |
| 0007 | the draft head's rows affine4 by default | PR #3477 OPEN, head `2894dfeed830` | no | re-seat; retire on #3477's landing sha |
| 0008 | prompt HC read-out as fused kernels, the shared expert read in place, wider head pieces | PR #3413 OPEN, head `10c84245ede1`, covers the read-out only | no | re-seat; split (shared-direct and head-piece stay local) |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | no PR, no branch | no | re-seat after 0005 |
| 0010 | a shared round priced from the environment (`ROUND_MS`, `DRAFT_ROW_MS`) | no PR, no branch; upstream's own measured pricing landed (#3728, #3755) | no | re-seat, then re-test against upstream's pricing |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | PR #3727 OPEN, head `d8608573a736`, covers the decode at load only | no, CHANGELOG.md only | re-seat the changelog hunk only |
| 0012 | the row cache can read through the page cache | no PR, no branch; depends on 0004 | no | re-seat with 0004 |
| 0013 | the window self-check can log its first differing row | no PR, no branch; depends on 0001 | no | re-seat with 0001 |
| 0014 | the drafter's BF16 linears re-coded to MXFP8 at load | PR #3218 OPEN, head `aa35a60e4be9` | no, CHANGELOG.md only | re-seat the changelog hunk only; retire on #3218's landing sha |
| 0015 | fp8 KV on every served stream and in the shared page pool | no PR, no branch; depends on 0003 | no | re-seat with 0003 |
| 0016 | the 12-bit read-out tile loads its blocks two groups ahead | no PR, no branch; depends on 0009 | no | re-seat with 0009 |
| 0017 | lane calls split over K on a cluster run on the fused form | PR #3475 OPEN, head `8b621a78e4f2` | no | re-seat; retire on #3475's landing sha |
| 0018 | the read-out's reduce and mix inside its products | no PR, no branch; depends on 0009 and 0017 | no | re-seat after 0009 and 0017 |
| 0019 | the fused split's kernel contract | #3475 carries the contract in its own shape (`lane_fused_records.zig`), not this file | yes | keep; it belongs with 0017 |

The PR state was read with `gh pr view N -R ashhart/TensorFold --json state,mergedAt,headRefName,headRefOid`:
#3413, #3475, #3477, #3218, #3726, #3727 and #3523 are all OPEN with `mergedAt` null; #3611 (a `core/quant` GPTQ
reader, no patch of this series touches `core/quant`) is MERGED, 2026-11-19T03:33:09Z. The fork's branches were read
with `git ls-remote --heads https://github.com/BadAd84/TensorFold.git`; `window-48-rows`,
`flashnext-copy-window-up` and `flashnext-gather-early-up` are on it, and
`gh api "repos/ashhart/TensorFold/pulls?state=all&head=BadAd84:<branch>"` returns empty for all three, so they are
unopened. Every other patch has neither a PR nor a branch.

## 2. Why each patch does not apply

`git apply --check` of each patch on a clean worktree of `d7c969c64` (the whole series through a scratch index:
1 of 19 applies). "drift" means main changed the same file for other work, the commit named; "depends on" means the
failing hunk's context or a file the patch edits is added by an earlier patch of the series, so it cannot apply to a
pristine tree at all.

| patch | files that fail | cause |
|---|---|---|
| 0001 | CHANGELOG.md, `cuda_lanes_load.zig`, `environment.zig` | drift: `cuda_lanes_load.zig` by `2931287ee` (the mixed PLE shard leaves the page cache, one line replaced); `environment.zig` by 13 commits since the base |
| 0002 | `core/lanes/stream.zig` | drift: `6486b5bcc` (#3617 step 0, 3 added lines in `stream.zig`) |
| 0003 | CHANGELOG.md, `cuda_disk.zig`, `tests/cuda/main.zig` | drift: `cuda_disk.zig` by `917f2070d` (#840, one kept image for states); `tests/cuda/main.zig` by `e54cb3492` (command help split out) |
| 0004 | CHANGELOG.md, `cuda_chunk.zig`, `environment.zig`, `environment_test.zig` | drift: `cuda_chunk.zig` by `b9a9ab314` (#3308, chunk settings through the startup parser); environment files depend on 0001 |
| 0005 | CHANGELOG.md, `cuda_prompt.zig`, `environment.zig`, `environment_test.zig`; `cuda_knobs.zig` missing | depends on 0003 (`cuda_prompt.zig`) and 0004 (`cuda_knobs.zig`, environment) |
| 0006 | CHANGELOG.md, `qmmf.cu`, `qmmf.zig`, `cuda_prompt.zig`, `environment.zig`, `environment_test.zig`; `cuda_knobs.zig` missing | depends on 0005 (qmmf and prompt) and 0004/0005 (environment, knobs) |
| 0007 | CHANGELOG.md, `cuda_mtp_draft.zig` | depends on 0001 (2 context lines in `cuda_mtp_draft.zig`) |
| 0008 | CHANGELOG.md, `environment.zig`, `environment_test.zig`, `tests/cuda/main.zig`; `cuda_knobs.zig` missing | depends on 0006 (environment) and 0003 (`tests/cuda/main.zig`, 8 lines) |
| 0009 | `cuda_prompt.zig` | depends on 0003 and 0005 |
| 0010 | CHANGELOG.md, `allocate.zig`, `depth.zig`, `windows.zig`, `cuda_lanes.zig`, `environment.zig`, `environment_test.zig` | drift: `allocate.zig` by `a5b58c743` (chained head and copy prices), `depth.zig` by 13 commits (the lane pricing campaign), `windows.zig` by 6 commits; `cuda_lanes.zig` and environment depend on 0004 and 0001 |
| 0011 | CHANGELOG.md | none in code: every code hunk applies |
| 0012 | `environment.zig`, `environment_test.zig`; `cuda_knobs.zig` and `cuda_ple_cache.zig` missing | depends on 0001 (environment) and 0004 (knobs, cache) |
| 0013 | `cuda_mtp_check.zig` | depends on 0001 (5 context lines) |
| 0014 | CHANGELOG.md | none in code: every code hunk applies |
| 0015 | CHANGELOG.md, `docs/recipes/flash-next-cuda.md`, `flashnext_attn.cu`, `cuda_batch.zig`, `cuda_glue.zig`, `cuda_images.zig`, `cuda_lanes_explain.zig`, `cuda_lanes_load.zig`, `cuda_launch.zig`, `cuda_media.zig`, `cuda_paging_batch_test.zig`, `cuda_snap.zig`; `flashnext_kv8.cuh`, `flashnext_kv8_pending.zig`, `flashnext_kv8_tests.zig` missing | depends on 0003 (all of it; 0003 creates the fp8 KV surface this patch pages) |
| 0016 | `qmmf_body.cuh`; `qmmf_q12.cuh` missing | depends on 0009 |
| 0017 | `qmmf.zig`, `cuda_prompt.zig`, `environment.zig`, `environment_test.zig`; `cuda_knobs.zig` missing | depends on 0005 and 0006 (qmmf, prompt) and 0004, 0005, 0006, 0008 (environment, knobs) |
| 0018 | `qmmf.cu`, `qmmf.zig`, `cuda_batch_hc.zig`, `cuda_batch_kernels.zig`, `cuda_prompt.zig`, `environment.zig`, `environment_test.zig`; `qmmf_q12.zig` and `cuda_knobs.zig` missing | depends on 0009 (q12) and 0005, 0006, 0017 (prompt, qmmf, environment) |
| 0019 | none | applies as cut |

The dependency attribution is not inferred from the file lists: for every failing hunk, the context lines main does
not have were matched against the earlier patches' added lines, and the earliest patch supplying them is the one
named (`work/Reseat/depends.py`, output in the appendix). For the five patches with real drift (0001, 0002, 0003,
0004, 0010), some context lines are supplied by no earlier patch, and those files are exactly the ones the commit log
shows main moved.

## 3. Content evidence that nothing was absorbed

For each lever, its distinctive markers on `d7c969c64` (whole tree searched; `grep -rIl`):

| patch | marker searched on main | result |
|---|---|---|
| 0001 | `probeServed`, `TF_FLASHNEXT_WINDOW_CHECK`, the boot self-check's log line | absent; `pub const max_rows: usize = 32` still in `cuda_mtp.zig` |
| 0002 | `resyncFrom`, `resync` in `zig/src/core/lanes` | absent (`resync` matches only the Electron app) |
| 0003 | `flashnext_kv8`, a `kv8` field in `flashnext.Options` | absent; `cuda_refusal.zig:66` still refuses `--kv-cache fp8` for a family without the field |
| 0004 | `ple_cache`, `cuda_ple_cache.zig`, `TF_FLASHNEXT_GATHER_READ` | absent; 0 commits to `cuda_ple*.zig` since the base |
| 0005 | `prompt_mx`, `TF_FLASHNEXT_PROMPT_MX128`, `mx128` in `qmmf.cu` | absent (0 lines in `qmmf.cu`) |
| 0006 | `prompt_mx2`, `TF_FLASHNEXT_PROMPT_GEMM2` | absent |
| 0007 | the `affine4` default in `cuda_mtp_load.zig` | absent: line 10 still reads `else "bf16"` |
| 0008 | `TF_FLASHNEXT_PROMPT_HC2`, `TF_FLASHNEXT_PROMPT_SHARED_DIRECT`, `TF_FLASHNEXT_HEAD_PIECE`, `fn_hc_writeback_moe_sh`, `flashnext_hcn.cu` | absent |
| 0009 | `qmmf_q12`, `TF_FLASHNEXT_HC_Q12` | absent |
| 0010 | `TF_FLASHNEXT_ROUND_MS`, `TF_FLASHNEXT_DRAFT_ROW_MS` | absent; `depth.zig` has its own measured `round_ms` table with no environment read |
| 0011 | `qwen_cuda_dequant.zig`, `max_image_tokens = 16384` | absent |
| 0012 | `TF_FLASHNEXT_GATHER_DIRECT` | absent |
| 0013 | `TF_FLASHNEXT_CHECK_LOG`, a differ log in `cuda_mtp_check.zig` | absent |
| 0014 | `TF_FLASHNEXT_MTP_WEIGHTS`, `cuda_mtp_mxfp8.zig` | absent |
| 0015 | `flashnext_kv8.cuh`, `flashnext_kv8_pending.zig` | absent (0003's files) |
| 0016 | `qmmf_q12.cuh` | absent (0009's file) |
| 0017 | `TF_FLASHNEXT_FUSED_SPLIT` | absent |
| 0018 | `TF_FLASHNEXT_READOUT_FUSE` | absent |
| 0019 | its added lines on main | absent, and the patch applies |

The same markers were put to `git log -S` over the whole range, one probe a patch
(`git -C work/upmain log --oneline -S'<marker>' 964174ea05..d7c969c64`): **0 commits for all 19**, so no commit in
the range added the code and later removed it either. The probes were `TF_FLASHNEXT_WINDOW_CHECK` (0001),
`resyncFrom` (0002), `Fp8KvUnsupported` (0003), `TF_FLASHNEXT_GATHER_READ` (0004), `TF_FLASHNEXT_PROMPT_MX128`
(0005), `TF_FLASHNEXT_PROMPT_GEMM2` (0006), `pub const default_mode` (0007), `TF_FLASHNEXT_PROMPT_HC2` (0008),
`TF_FLASHNEXT_HC_Q12` (0009), `TF_FLASHNEXT_ROUND_MS` (0010), `pub const max_image_tokens` (0011),
`TF_FLASHNEXT_GATHER_DIRECT` (0012), `TF_FLASHNEXT_CHECK_LOG` (0013), `TF_FLASHNEXT_MTP_WEIGHTS` (0014),
`TF_FLASHNEXT_KV_PAGE_TEST` (0015), `Raw qr[MODE == Q12` (0016), `TF_FLASHNEXT_FUSED_SPLIT` (0017),
`TF_FLASHNEXT_READOUT_FUSE` (0018), `served_fused` (0019).

A second, per-patch measure: of each patch's substantive added lines (an identifier, 12+ columns, not a one-line
comment, not a bare brace), how many appear verbatim in the file the patch names, or in the whole `zig/` source when
that file is absent from main (a file the patch creates, or one an earlier patch creates). Those are base code the
patch re-adds in a rewritten hunk, not lever code; the patches
with the highest counts were sampled for lever keywords (`fp8`, `kv8`, `q12`, `ple_cache`, `round_ms`, `mx128`,
`hcn`, `resync`, `fused`, `gather_read`) and the only matches were upstream's own pre-existing code
(`attnFused` in `cuda_glue.zig`, `if (fused)` in `cuda_batch.zig`).

| patch | substantive added lines present on main |
|---|---|
| 0001 | 13 of 98 |
| 0002 | 27 of 247 |
| 0003 | 143 of 785 |
| 0004 | 139 of 773 |
| 0005 | 18 of 149 |
| 0006 | 11 of 48 |
| 0007 | 0 of 4 |
| 0008 | 213 of 799 |
| 0009 | 99 of 396 |
| 0010 | 97 of 236 |
| 0011 | 60 of 343 |
| 0012 | 3 of 11 |
| 0013 | 0 of 5 |
| 0014 | 11 of 69 |
| 0015 | 21 of 238 |
| 0016 | 2 of 19 |
| 0017 | 3 of 30 |
| 0018 | 36 of 275 |
| 0019 | 10 of 34 |

## 4. What moved upstream on our surface, and what it was

The commits behind the drift above, read with `git log --oneline 964174ea05..d7c969c64 -- <file>`:

- `environment.zig` 13 commits and `environment_test.zig` 10 commits since the base. This is the single most common
  conflict: any patch that adds a rule to the environment table fails there, and nine patches do.
- `cuda_lanes_load.zig` `2931287ee` "flashnext cuda: the mixed PLE shard and the nested shards leave the page cache
  after load" (one line replaced), which is why 0001 stops at that file.
- `core/lanes/stream.zig` `6486b5bcc` "server: every message's start in the rendered prompt, beside the chunk plan
  (#3617 step 0)" (3 added lines), which is 0002's only conflict.
- `cuda_disk.zig` `917f2070d` "cuda: one kept image for states in device buffers, Gemma 4 on disk (#840)" and
  `tests/cuda/main.zig` `e54cb3492` "cuda tests: split command help to keep the runner under 600 lines", 0003's.
- `cuda_chunk.zig` `b9a9ab314` "feat(flashnext): read the chunk settings through the startup parser (#3308)", 0004's.
- `allocate.zig` `a5b58c743`, `depth.zig` 13 commits, `windows.zig` 6 commits: the lane pricing campaign
  (PR #3728 "price a lone stream's copy windows from its own timed rounds", merged 2026-11-19; PR #3755 "shared
  rounds price the drafter's fixed work once", merged 2026-11-18), which is 0010's.

Nothing in that list implements any lever of this series; each is other work in the same file. The one upstream
implementation on the same ground is `flashnext_hcf.cu` ("#952's hyper-connection read-out ... on prompt tiles"), which
predates the base and co-exists with our 0008/PR #3413 read-out; it is a different design (factored groups) and none of
0008's added lines are in it.

## 5. Patches whose retirement the owner should confirm

These rest on judgement, not on a content match. None is absorbed; each is a question of whether to keep carrying a
lever whose ground upstream has moved onto or whose upstream PR covers part of it.

1. **0010** (a round priced from the environment). Upstream's own measured pricing landed while our base sat: PR #3728
   (merged 2026-11-19) and PR #3755 (merged 2026-11-18), plus 13 commits in `depth.zig` and 6 in `windows.zig`. The
   mechanism differs (measured tables vs an environment override), so 0010 is not superseded by content; whether the
   override still earns its keep needs the A/B after the re-seat.
2. **0008** (read-out fused). PR #3413 covers the read-out fusion only; `PROMPT_SHARED_DIRECT` and `HEAD_PIECE` are not
   in it, and upstream's own `flashnext_hcf.cu` holds the same ground as the read-out. Whether to keep all three parts
   in one local patch, or to retire the read-out part on #3413's landing and carry the other two, is a split decision.
3. **0005** (prompt chunk). PR #3726 covers the 3,072-row chunk; the MX128 prompt tile is not in any PR. Whether MX128
   is worth a second PR or stays local is a split decision. Upstream also moved chunk selection itself (`b9a9ab314`,
   the merged #3591, plus the base's own 8,192-row lone chunk), so the chunk half is re-tested against that first.
4. **0011** (vision). PR #3727 covers the decode at load; `max_image_tokens = 16384` is not in it. Keep the constant
   local or add it to the PR.
5. **0001** (copy window). Two unopened branches hold this lever, `window-48-rows` (an older cut: its own commits take
   copy windows to 64 rows and add the 48-row bench) and `flashnext-copy-window-up` (cut against newer main, head
   `d8c4dd5a80c1`). Carrying the 19-patch version or the newer
   branch cut is a choice; upstream's `TF_FLASHNEXT_WINDOW_ROWS` lowers the drafting round's rows and is not the same
   knob (`max_rows` is unchanged at 32).
6. **0004** (row cache). The gather-early sub-lever has an unopened branch; the row cache itself does not. Keep local
   or open a PR for the cache is the owner's call.
7. **0003 and 0015** (fp8 KV). Main still refuses `--kv-cache fp8` for this family by name. They are one lever in two
   patches and stay local until a PR exists; no retirement question, but no upstream path either.

## 6. Corrections to earlier records

- `patches/main-964174ea05/RECORD.md` says of 0008: "`flashnext_hc.cu` and `flashnext_hcn.cu` are ours (absent
  upstream)". `flashnext_hc.cu` is present at the base (`git cat-file -e 964174ea05:zig/kernels/cuda/flashnext_hc.cu`
  succeeds) and present on main; only `flashnext_hcn.cu` is created by the patch. The same record's "no patch is
  retired: upstream has absorbed none of them" still holds on `d7c969c64`, now by content per table 3.
- `docs/RESTACK-main-964174ea05.md` ends at `964174ea05`; this document is the next base's classification, not a
  re-seat. The patches still apply to `964174ea05` only, and `patches/main-964174ea05/apply.sh --check` was not run
  against `d7c969c64` (it refuses any HEAD but its base by design).

## 7. How this was produced

    git -C work/upmain fetch origin main
    git -C work/upmain rev-parse origin/main                     # d7c969c649cec5e85a0e0b964c863cfb97172e30
    git -C work/upmain worktree add --detach work/Reseat/main d7c969c649cec5e85a0e0b964c863cfb97172e30
    # the cumulative check, a scratch index, nothing written to the tree:
    GIT_INDEX_FILE=work/Reseat/chain.index git -C work/Reseat/main read-tree HEAD
    GIT_INDEX_FILE=work/Reseat/chain.index git -C work/Reseat/main apply --cached patches/main-964174ea05/NNNN-*.patch
    # per patch, against the pristine tree: git -C work/Reseat/main apply --check --whitespace=nowarn <patch>
    # content: python work/Reseat/presence.py and analyse.py (markers, substantive lines), depends.py (context owners)
    # no commit adds or removes a marker: git -C work/upmain log --oneline -S'<marker>' 964174ea05..d7c969c64
    gh pr view N -R ashhart/TensorFold --json state,mergedAt,headRefName,headRefOid
    git ls-remote --heads https://github.com/BadAd84/TensorFold.git

The scripts and their outputs are kept under `work/Reseat/` (gitignored) until the next re-seat replaces them;
the commands above recreate them. No
build, test or GPU run was made in this lane; a retired patch's test is a later step, and nothing is retired here.

## Appendix: machine output the tables are built from

The cumulative chain ends `TOTAL applied 1` (0019). The per-patch presence, failure lists and upstream commit counts
are the output of `work/Reseat/analyse.py patches/main-964174ea05 work/Reseat/main 964174ea05`, and the context
attribution is `work/Reseat/depends.py patches/main-964174ea05 work/Reseat/main`; the numbers quoted above are its
lines for the corresponding patch (for example, 0009's `cuda_prompt.zig: 2 missing context line(s); earliest earlier
patch supplying them: 0003 (1), 0005 (1)`, and 0015's ten files each naming 0003).

The presence counts were then recomputed independently, with no git involved, from a `git archive` extraction of
`d7c969c649cec5e85a0e0b964c863cfb97172e30` (`work/Reseat/verify_presence.py`, output
`work/Reseat/verify.txt`): all 19 came out to the same counts, line for line, which also confirms the set of files
that main does not have.
