# TensorFold main `1ece6e6db` + r5-dev: the single dev engine

The composition of every measured candidate on the r5 base: the twenty core levers, the INT4 port with its serving
pins, the persistent KV tier with the pool's cache refusal and the whole-ask budget, the bf16 draft-head fix, the
int4 contract suite with the tolerance branch's allowance, controls and gate-4 margin, and the asked-cache split the
composed gate forced. One directory, one series, unique numbers, and the tree a device build reads when it applies a
patch directory in glob order.

    ./apply.sh --check TREE     # all 36 apply in order, nothing written
    ./apply.sh TREE             # apply them on a pristine checkout at 1ece6e6d

Base: upstream TensorFold `main` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. An image of this series serves
`azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` only (the routing width is a build-time constant and the config
check refuses the FP4 checkpoint by name, as `patches/main-1ece6e6db-r5-int4/README.md` states).

## This is the dev stack; the granular packages are provenance

The dev engine is this composition, not any one of its sources. `patches/main-1ece6e6db-r5` (the twenty core levers),
`patches/main-1ece6e6db-r5-int4`, `patches/main-1ece6e6db-r5-kvtier`, `patches/main-1ece6e6db-r5-kvtier-pool`,
`patches/main-1ece6e6db-r5-int4-kvtier` and `patches/main-1ece6e6db-r5-drafthead-bf16` stay in the tree as
provenance and as alternatives an arm can choose; they are **not** the stack the dev engine builds from, and a new
beneficial patch lands by joining this composition (its own patch, its RECORD row, its pins) rather than by growing a
new side package. `RECORD.md` names, for every patch here, the package or branch it came from and whether its text was
edited in the port, so removing a source package or branch cannot lose the record of what it contributed.

## The patches

| # | patch | lever |
|---|---|---|
| 0001 | `rows` | a lone stream's copy window grows to the boot self-check's largest row-exact width; a verify window with a pending-row log takes the row-by-row DeltaNet |
| 0002 | `copy-resync` | copy re-sync past an edit, the copy ramp and the miss rules |
| 0003 | `kv8` | `--kv-cache fp8` for Flash Next: e4m3 keys and values, a power-of-two scale a row |
| 0004 | `ngram-row-cache` | the n-gram table's rows through a direct-mapped row cache; a drafted token's rows asked for while the head drafts; a chunk's rows while the chunk before it runs |
| 0005 | `prompt-sync-mx128` | prompt passes drain less on one rank; MXFP8 projections above N columns take the relaxed 128 x 128 prompt tile |
| 0006 | `prompt-gemm2` | the MX128 tile in two stages, two blocks an SM |
| 0007 | `draft-head-4bit` | the draft head's rows 4-bit by default (`TF_FLASHNEXT_DRAFT_HEAD=affine4`; `bf16` restores) |
| 0008 | `shared-direct-head-piece` | the prompt MoE write-back reads the shared expert's fp32 output in place; the head piece is bounded, with the pass scratch sized for it |
| 0009 | `readout-q12` | hyper-connection read-outs from a lossless 12-bit copy |
| 0010 | `round-cost` | a shared round priced from the environment |
| 0011 | `vision` | vision tower linears decoded at load; image rows up to 16,384 |
| 0012 | `gather-direct` | the row cache can read through the page cache |
| 0013 | `check-log` | the window self-check logs its first differing row |
| 0014 | `mtp-mxfp8` | the drafter's BF16 linears re-coded to MXFP8 at load |
| 0015 | `kv8-pages` | fp8 KV on every served stream and in the shared page pool |
| 0016 | `readout-q12-ahead` | 0009's 12-bit read-out tile loads its blocks two groups ahead |
| 0017 | `fused-split` | lane calls split over K on a cluster run on the fused form |
| 0018 | `readout-fuse` | the read-out's reduce and mix inside its products |
| 0019 | `fused-split-contract` | the fused split's kernel contract |
| 0020 | `serving-pins` | the r5 series' serving pins |
| 0021 | `int4-autoround` | the INT4 port: production's checkpoint admitted and served, its four settings read through the engine's table, its tests collected |
| 0022 | `int4-serving-pins` | the INT4 port's 17 serving-pin rows |
| 0023 | `kv-tier-fp8` | the persistent KV tier's fp8-capable state image and its conversation store |
| 0024 | `kv-tier-dedup` | an append keeps one state where the rewind applies, halving the write |
| 0025 | `kv-tier-pool` | a plan that leaves the prompt cache no bytes refuses the tier by name |
| 0026 | `kv-tier-full-ask` | a family that declares no snapshot slots is budgeted the whole prompt-cache ask |
| 0027 | `draft-head-format` | the drafter's recode window closes before the draft head loads; a projection in another coding stops the start by name (`DraftHeadFormat`) |
| 0028 | `draft-head-format-pins` | 0027's `cuda_mtp.zig` pin row, regenerated from the merged bytes |
| 0029 | `int4-contract-suite` | PR #4183's contract suite: the int4 experts and head through gates 1-4, the float64 reference, the allowance model and the two original controls |
| 0030 | `int4-contract-verb` | the `int4-contract` runner verb, its build step and its usage line |
| 0031 | `int4-gateup-allowance` | the tightened gate/up allowance (the sums' second count removed) and the arithmetic pinned on the host |
| 0032 | `int4-controls-allowances` | the epilogue's scalar model and three planted controls on the gate/up form, gate 4's derived margin, and `docs/int4-contract-allowances.md` |
| 0033 | `serving-pins` | the merged serving pins (`root.zig`) |
| 0034 | `cache-slots-asked` | the pool package's own named-slots test: its `named8` arm expected an asked cache beside TF_KV_SHARE as copies, contradicting the kept-pages behaviour #2987 pins; the test now pins copied 0 and the rest as kept pages, the engine untouched |
| 0035 | `int4-config-shared-width` | the int4 port splits the shared expert's width from the routed experts'; the config test's wider-shared fixture now starts from `wt.shared_w` (the value the check compares), not `wt.moe_w` |
| 0036 | `int4-test-fixtures` | the other two full-suite findings: the int4 dense dispatch is narrowed to the group sizes the kernel builds (64 or 128), and the split-lane fixture sets `shared_width`, the field the int4 port reads; both tests predate those fields |

## The serve shape and what the env and launcher do not state

Production's shape: `--parallel 8`, `--context 262144`, fp8 KV, the KV page pool (`TF_FLASHNEXT_KV_PAGES=4096`), the
KV tier on its own budget, and the INT4 drafter arm the int4 package measured (`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`,
`TF_FLASHNEXT_DRAFTS_GREEDY=15`, `TF_FLASHNEXT_SHARED_DRAFTS=0`, `TF_FLASHNEXT_GREEDY_WIDE=8`), with
`--prompt-cache-gib 6 --prompt-cache-disk <root> --learn-conversations --learn-gib 60 --learn-daily-gib 200
--learn-min-free-gib 20`.

The coverage gate against this tree is **red**, and the four settings are 0021's own rows, all in `dev.env`'s scope:

    python scripts/qwen38/zig/target/env/check-env-coverage.py --table <this tree>/zig/src/platform/environment.zig \
      --dev scripts/qwen38/zig/target/env/dev.env --register scripts/qwen38/zig/target/env/register.env \
      --scopes flashnext,cuda,common
    coverage: 99 settings in scope, set 95, missing 4, ...
    MISSING TF_FLASHNEXT_HEAD_ROW_TILES
    MISSING TF_FLASHNEXT_INT4_PROMPT_DOWN
    MISSING TF_FLASHNEXT_INT4_PROMPT_GATE_UP
    MISSING TF_FLASHNEXT_INT4_TILE
    STALE TF_FLASHNEXT_HEAD_ROW_TILES / TF_FLASHNEXT_INT4_PROMPT_GATE_UP (the register still calls them retired)

`dev.env`'s own citations pass (`dev-env: 0 setting(s) without a citation`). The four values the launcher and the
engine already use are `TF_FLASHNEXT_HEAD_ROW_TILES=2` and `TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1` (both set inline by
`scripts/qwen38/zig/qwen6-start.sh:54`), and the engine's own defaults `TF_FLASHNEXT_INT4_TILE=16` and
`TF_FLASHNEXT_INT4_PROMPT_DOWN=1`. Writing them into `dev.env` (and turning the register's two `retired` lines into
settings) is an env promotion outside this package's scope; the composition is the tree that makes it due.

Launcher defaults a patch here assumes and `scripts/qwen38/zig/qwen6-start.sh` does not carry:

- **The KV tier (0023-0026).** The tier exists only if the engine is started with `--learn-conversations` and its
  `--learn-gib/--learn-daily-gib/--learn-min-free-gib` budget, and 0026's whole-ask budget is the `--prompt-cache-gib`
  ask. The launcher forwards none of them and starts the recipe's `start.sh` with `PREPARE=0 PARALLEL=8` only, so the
  tier and the refusal are inert on that boot.
- **The INT4 arm (0021).** The launcher does not set `CHECKPOINT=int4`, `VISION=0` or `KV_DTYPE=fp8`; those are the
  recipe's variables and the deployed image is the FP4 checkpoint's. The INT4 route needs its own image and boot line
  (the package README's block), not just this tree.
- **The draft head (0027).** The defect needs `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` and the arm is
  `TF_FLASHNEXT_DRAFT_HEAD=bf16`; the launcher sets neither (it sets `TF_FLASHNEXT_MTP_FP8`, which this engine does not
  read) and leaves the head at `affine4`, where the fix is inert.

## Gates

Every row is the gate run's own line; the whole log is the run named in `RECORD.md`. Host: Paperclip (x86-64, 16
threads, Zig 0.17.0, nvcc 13.3.73), under `flock ~/work/host.lock`, on a pristine `git archive` of `1ece6e6d` staged and
blob-verified against `git ls-tree`, then `apply.sh` applied. Host suites run: `test-environment-host`,
`test-gradient-serving`, `test-qwen-serving-host`, `test-flashnext-int4-host`, `test-int4-host`,
`test-flashnext-draft-head-host`, `test-prompt-cache-host`, `test-cache-store-host`, `test-learn-recovery`,
`test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host`, `test-kernel-contract`,
`test-cuda-cache-budget-host`, and `test-cuda-host`.

| step | result |
|---|---|
| staged tree against `git ls-tree` | see `RECORD.md`, Checks |
| `apply.sh --check` / `apply.sh` | see `RECORD.md` |
| `zig fmt --check build.zig zig` | rc 0 |
| lean, each tree's own checker; `lean_new.py` 0 new | see `RECORD.md` |
| `pincheck.py` | `files 170 failing 0` |
| host suites (the list in `RECORD.md`) | rc 0 |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | rc 0 |
| `zig build compile-cuda-tests`, `-Dtarget=aarch64-linux-gnu` | rc 0 |
| `zig build -Dnvcc=... compile-cuda-tests` native | rc 0, 969 s |
| the same, `-Dtarget=aarch64-linux-gnu` | rc 0, 945 s |
| `zig build -Dfixed-cpu test-cuda-host` | rc 1 on the 35-patch tree: `7666/7715 tests passed (44 skipped, 4 failed, 1 crashed)`. 0034's step reads `22/22` after its fix; 0035 and 0036 target the other failures (the config fixture, the int4 dense dispatch and the split-lane `shared_width`), and the run that observes them had not completed at hand-off; the log is `~/work/DevComp/gate2.log` on Paperclip |

## What this package does not do

- It adds no engine line of its own: 0001-0026 are their sources' bytes, 0027 and 0028 are the draft-head pair with
  the one hunk re-cut and the one pin row regenerated, 0029-0032 are PR #4183's contract suite and the tolerance
  branch's three commits, ported with the adaptations `CHANGES.md` lists, 0033 is the merged pin row, and 0034 and
  0035 correct the two source tests the composed gate proved stale (the pool's named-slots expectation and the int4
  shared-width fixture); no engine line is changed by either.
- No device result is claimed for this composition. The contract suite's device receipt belongs to the tolerance
  branch's head; the suite runs here on the host (`test-int4-host`, `test-kernel-contract`) and its kernels are the same
  groups-of-128 symbols the branch proved.
- It does not close the INT4 package's gap against the maintainer's steps on issue #3368, the tier's design items 8
  to 10 (staging ring, store pin, block-name lineage), or the env and launcher gaps above.
