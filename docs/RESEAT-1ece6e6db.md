# Re-seat of our patch series onto upstream main `1ece6e6db` (2026-11-20)

The series under test is `patches/main-964174ea05` (19 patches), re-seated as `patches/main-1ece6e6db` (19 levers +
a 20th pins patch). Host gates ran on Paperclip (x86-64); no GPU was touched, nothing was pushed, nothing posted.

- Upstream `ashhart/TensorFold` main: **`1ece6e6dbbc073582d50738ce8e73e3c3261a73b`** (2026-11-20 13:01 UTC,
  "changelog: #4202 under Unreleased"), read from `git -C work/upmain rev-parse origin/main` after
  `git fetch origin main`.
- The series' own base: `964174ea05879e6dde1de1198a3aae3ef8b46a3b` (2026-11-15, `v1.2.9-33-g964174ea05`).
- **1,188 commits** between the two (`git log --oneline 964174ea05..1ece6e6db | wc -l`).
- 23 commits in that range are ours (`git log --author=BadAd84`), from three merged pull requests: #3726 (the
  3,072-row prompt pass), #3413 (the fused read-out) and #3611 (a `core/quant` GPTQ reader). #2044 (GLM EXL3) touches
  no file this series changes.

Merged PRs of ours, read with `gh pr list --repo ashhart/TensorFold --author BadAd84 --state merged`:

| PR | merged | merge commit | what it carries here |
|---|---|---|---|
| #3611 | 2026-11-19T03:33:09Z | `0f8e35a1a` | a `core/quant` GPTQ reader; no patch of this series touches `core/quant` |
| #3726 | 2026-11-19T22:50:19Z | `bc99bab7b` (code `e172bcc29`) | 0005's 3,072-row chunk: **absorbed** |
| #2044 | 2026-11-20T08:14:31Z | `82e8927f9` | GLM EXL3 decode windows; no patch of this series |
| #3413 | 2026-11-20T11:10:34Z | `9748adc7e` (code `12233bee5`) | 0008's fused read-out: **absorbed** |

The lever PRs are still open: #4009 (gather early), #4075 (copy window), #3477 (draft head), #3727 (vision), #3218
(mxfp8), #3475 (fused split), #3523 (config widths), #4183 (INT4). Issue #4107 is another contributor's fp8 KV, the
ground 0003/0015 sit on without a submission of ours.

## 1. One row a patch

| patch | lever | verdict | evidence |
|---|---|---|---|
| 0001 | copy window to the self-check's width; the row-by-row DeltaNet for a log-carrying verify window | re-seated | probe block before main's `dropPageCache(gpa, io, dir, ...)`; rule after `TF_QMMF_HALF_BELOW`; 0 added lines lost |
| 0002 | copy re-sync, the ramp and the miss rules | re-seated, 3-way only | 0 lost |
| 0003 | `--kv-cache fp8` for Flash Next | re-seated | `#840` moved `View.copy` into `native/cuda_kept.zig`; the refusal is `View.copyable` called by the shared copy (2 lines); usage line moved to `main_usage.zig`; 0 lever lines lost |
| 0004 | n-gram rows through a row cache, draft-ahead, gather-early | re-seated | 8 rules after 0001's; 0 lost |
| 0005 | prompt sync + the MX128 tile (the 3,072-row chunk is main's) | re-seated, chunk half **retired** | absorbed by `e172bcc29` / #3726: main's `default_chunk = 3072`, `check(null, 3072)`, and the 3 GiB scratch test; 4 hunk lines dropped |
| 0006 | the MX128 tile in two stages | re-seated | 0 lost |
| 0007 | the draft head 4-bit by default | re-seated | 0 lost; main still reads `else "bf16"` |
| 0008 | shared-direct write-back + head piece (the fused read-out is main's) | re-seated, read-out half **retired** | absorbed by `12233bee5` / #3413: `readout_fused.zig`, `cuda_tiles.zig`'s `readoutFused`/`pickDown`, `flashnext_hcn.cuh`, `tests/cuda/flashnext_readout_fused.zig`; 935 lines dropped |
| 0009 | 12-bit read-out copy | re-seated | 0 lost |
| 0010 | a shared round priced from the environment | re-seated | both `rate()` sites re-expressed as `rateRows(..., base, ..., head.draft_row_ms)` on main's overhead; fields in both `allocateDrafts` literals; main's moved depth tests kept |
| 0011 | vision decode at load, image rows 16,384 | re-seated | 0 lost |
| 0012 | row cache through the page cache | re-seated | 0 lost |
| 0013 | the self-check logs its first differing row | re-seated | 0 lost |
| 0014 | the drafter's linears as MXFP8 | re-seated | 0 lost |
| 0015 | fp8 KV on every stream and in the pool | re-seated | main's `p.arena.buf.ptr` with the patch's `.kv`; 0 lever lines lost |
| 0016 | the 12-bit tile loads two groups ahead | re-seated | block after main's `TF_QMMF_WFIRST` `#endif` |
| 0017 | lane calls split over K on the fused form | re-seated | `.cluster` narrowed with `and !fs` beside main's `pdl` line; rule and case seated |
| 0018 | reduce and mix inside the read-out's products | re-seated | 0 lost |
| 0019 | the fused split's kernel contract | re-seated | 0 lost |
| 0020 | serving pins for the files the series edits | new plumbing | 27 rows re-hashed; `pincheck` failing 0 |

No patch is wholly retired. The two partially absorbed ones are recorded in `patches/main-1ece6e6db/RETIRED.md` with
the absorbing commit, the PR and the evidence on main.

## 2. Content evidence

For each lever, its distinctive markers on `1ece6e6db` (whole tree, `grep -rIl`): `probeServed`, `resyncFrom`,
`Fp8KvUnsupported`, `ple_cache`, `TF_FLASHNEXT_PROMPT_MX128`, `TF_FLASHNEXT_PROMPT_SYNC`, `TF_FLASHNEXT_PROMPT_GEMM2`,
`TF_FLASHNEXT_HC_Q12`, `TF_FLASHNEXT_ROUND_MS`, `TF_FLASHNEXT_GATHER_DIRECT`, `TF_FLASHNEXT_CHECK_LOG`,
`TF_FLASHNEXT_MTP_WEIGHTS`, `TF_FLASHNEXT_FUSED_SPLIT`, `TF_FLASHNEXT_READOUT_FUSE` are absent from `main`'s code (the
only hits are our own receipt doc `docs/receipts/flashnext-prompt-chunk3072/README.md`, which names knobs the merged
#3726 does not carry). `TF_FLASHNEXT_READOUT_FUSED` and `flashnext_hcn` are present because #3413 landed them.
`TF_FLASHNEXT_DRAFT_HEAD` exists only as the environment read (#3477 not merged) and `default_mode` is absent.

`git log -S<marker> 964174ea05..1ece6e6db` finds no commit that added a lever's marker and later removed it, apart
from `76fb593b1` (our own #3726 receipt doc) and the #3413 series for `TF_FLASHNEXT_READOUT_FUSED`.

The per-patch added-line comparison (`work/Reseat2/compare_added.py patches/main-964174ea05 work/Reseat2/out`) shows
exactly the recorded losses and no others:

    lost/new added lines: 0001 0/0, 0002 0/0, 0003 2/6, 0004 0/0, 0005 4/0, 0006 0/0, 0007 0/0,
    0008 935/0, 0009 0/0, 0010 4/4, 0011 0/0, 0012 0/0, 0013 0/0, 0014 0/0, 0015 1/1,
    0016 0/0, 0017 0/0, 0018 0/0, 0019 0/0

0003's two lost lines are the old comment and the usage line, both re-homed (the same text appears as a doc comment
and in `main_usage.zig`); 0010's and 0015's are the same lines re-expressed against main's structure.

## 3. Gates

Every tree was verified blob by blob before a gate ran: `git ls-tree -r` of the tree, every file's git blob hash
recomputed on the host (`verify_blobs.py`), `12,601` files for the base and `12,620` for base + series, plus the
package applied to a pristine archive reproducing the series tree exactly.

| gate | where | result |
|---|---|---|
| `apply.sh --check` (20 patches) | pristine worktree at the base | `20 patches apply on 1ece6e6dbb... in order (nothing written)` |
| `zig fmt --check build.zig zig` | Paperclip for the series before the two fixes, and the final series locally (Zig 0.17.0 formatter) | rc 0 both |
| `zig build test-environment-host` | Paperclip, series before the two fixes | rc 0; the final series' run was queued on the host lock |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | Paperclip, series before the two fixes | rc 0; `pincheck.py` reads `files 169 failing 0` on the final tree |
| `zig build -Dfixed-cpu test-kernel-contract` | Paperclip, final series | rc 0; 259/259 compiled tests passed (its `N/A ... not served there` lines are the chip map's own) |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | Paperclip, series (cross-compile) | **not observed**: re-launched detached behind `~/work/host.lock`, which another lane's `box/runall.sh` held continuously; the pre-fix run failed only on the two defects below, both fixed |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | Paperclip, series (cross-compile) | **not observed**, same queue; the native `test-kernel-contract` step compiles the engine here |
| `pincheck.py` on the base and the series | Paperclip | `files 169 failing 0` both |

The first run of the cross-compiles failed with two compile errors the re-seat itself had introduced: a duplicated
`.cluster` field in `qmmf.zig` (0017's resolution kept main's line beside the narrowed one) and a lost
`cuda_tiles.zig` import in `cuda_batch_hc.zig` (main's own `promptFused` reads `tiles.fused_rows`; 0008's resolution
had replaced the import instead of adding to it). Both were fixed in the resolvers and the whole series re-seated;
the table above is the fixed series.

## 4. What was not run

- Any GPU work: golden replies, decode throughput, `tf-cuda-test` execution, `flashnext-pages` and the other device
  tests. This lane has no GPU window (spark6 was in another lane's receipt window).
- A repeated measurement of the served numbers in `patches/main-964174ea05/README.md`. They stand as the last full
  A/B of the series, on the old base; the first window on this base must reproduce them before any cell is quoted.
- `zig build test` (the whole host suite) beyond the named gates.

## 5. How this was produced

    git -C work/upmain fetch origin main
    git -C work/upmain rev-parse origin/main                  # 1ece6e6dbbc073582d50738ce8e73e3c3261a73b
    # the old series' CHANGELOG bullets only, to rebuild the new base's Unreleased section
    python work/Reseat2/reseat_any.py work/Reseat2/new 964174ea05... patches/main-964174ea05 work/Reseat2/out work/Reseat2/res
    # 0005 and 0008 reduced first (reduce8.py), their bullets rewritten (fix_series.py, fix_series2.py)
    # each patch is the diff of the staged trees; resolvers under work/Reseat2/res/resolve_NNNN.py
    # pins: python work/Reseat2/mkpins.py <series tree> ; git diff --cached HEAD -- zig/tests/fixtures/gradient-serving.tsv
    # host gates: ~/tools/zig-x86_64-linux-0.17.0/zig under flock ~/work/host.lock, umask 022
    # blob proof: work/Reseat2/ship/verify_blobs.py DIR <git ls-tree -r> output

The scripts and their outputs live under `work/Reseat2/` (gitignored) until the next re-seat replaces them.
