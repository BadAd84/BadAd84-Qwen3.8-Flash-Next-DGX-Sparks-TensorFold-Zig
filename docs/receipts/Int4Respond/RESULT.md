# The four asks on the rebased branch, and what each one now rests on

## Facts about the branch

| item | value |
|---|---|
| upstream main (base of every receipt below) | `7bd7081e061ca22e3431d2342cd66104dd5fe320` |
| rebased head, local branch `cuda-int4-respond` in `work/Int4Respond/tree` | `984556bf50ac4e603695596444772f27bd93bd01` |
| commits on the branch | six: the PR's four, then the contract coverage and the dispatch |
| diff against main | 23 files, 2030 insertions, 4 deletions (two re-pinned fixture rows, two reflowed doc comments) |
| author and committer of every commit | `BadAd84 <BadAd84@users.noreply.github.com>`, every commit signed (`G`) |
| lean, base versus head, each tree's own checker | 165 versus 165, 0 new |
| `tools/pr_check.py --base 7bd7081e0` | 0 errors, 1 advisory warning (no Unreleased CHANGELOG bullet naming #4183) |
| `git diff --check origin/main` | clean |

Nothing was pushed, and the pull request was not touched.

## Ask 1: rebase, resolve, preserve, regenerate, re-pin

Done. The file by file record, with both sides of each conflict and why, is in `RESOLUTIONS.md`. The short form:

- Rebased `--onto 7bd7081e0` from the old merge base `e702cfdae`; the branch was 392 commits behind.
- Two files conflicted: `zig/kernels/cuda/contract_controls_set.cu` (kept both control headers) and
  `zig/tests/fixtures/gradient-serving.tsv` (main's manifest, with the two rows the merged tree moves regenerated).
- The registration lists that merged cleanly were diffed against main and are additive: `kernels.zig` +1,
  `root.zig` +3, `contract_limits.zig` +1, `contract_controls_set.cu` +1, `build/cuda.zig` +1,
  `build/cuda_kernels.zig` +1, `registry_joins.zig` +1, `contract_after.zig` +2 with its one doc line rewritten.
  Main's newer registrations (every image, the newer control headers, the newer limits-image names) are all still
  reached.
- The pin was regenerated from the merged bytes, not edited by hand: `work/Int4Respond/tools/repin.py` hashes the
  merged tree and refuses to write if any row other than the two named ones would change (it did not fire for the
  other 167). The rows are `kernels.zig` `654168cb...` and `root.zig` `9eee99ac...`. The branch's own provenance
  text cited `main 32c4e3d8f (#3368 ...)`, a changelog commit that does not register the image; it now reads
  `; #4183 (...)` in the fixture's own PR-number form.
- Serving sources main had moved are main's own rows, kept as main wrote them; only the two files this change moves
  are re-pinned.

## Ask 2: gates 1 to 4 and byte-replacement coverage for the prompt-down BF16 form

The code decided this, and the answer was that the form was compiled and never registered.

- `fn_int4.cu` instantiates `int4_prompt_kernel` twice for the routed down: `TF_INT4_PROMPT(128, 0, 2)` (fp32 out)
  and `TF_INT4_PROMPT(128, 3, 2)` (bf16 out). `int4.zig` resolves both (`prompt_symbols`, `prompt_stages`,
  `downPrompt`'s `g = @intFromBool(!f32_out)`) and the registry declares all three prompt launches
  (`int4_records.zig`, 21 launches in total).
- `contract_int4.zig` drove only `f32_out = true`, at the new launch and at its reference launch, so epilogue 3 of
  the prompt kernel had no gate and no byte comparison.
- The change adds `Kind.prompt_down_bf16`: same served shapes (64 and 200 token rows at the checkpoint's 2,560 by
  640), same tiles, `out = .bf16`, `replaces = "the routed down to bf16 of 16-pair items"`, the launch at
  `f32_out = false`, and the reference at the plain `int4.down(..., false, ..., plan_tile)` form. It is the seventh of
the eight forms in the list of ten entries (the other two are controls).
- Why the byte comparison is legitimate rather than hopeful: both kernels share `store<NT, MATS, EPI>` (EPI 3 is the
  same `__floats2bfloat162_rn` store), and both accumulate a group's k32 blocks in order, each block's two k16 mma
  steps in order, then `fmaf(group sum, scale, acc)` in group order; a row's bits depend on its own inputs and
  weights alone, never on the row tile, the item or the column tile. The prompt tile and item count differ from the
  plain form's, and that is exactly what gate 3 now proves byte for byte.
- Gates 1 to 4 run through the same harness hooks the fp32 entry uses (`prepare`, `run`, `reference`, `bounds`,
  `simulate`, `replaced`): gate 1 plants NaN and both infinities, gate 2 runs five times and checks inputs, guards
  and overlap, gate 3 walks both served shapes and compares to the plain bf16 form byte for byte, gate 4 replays the
  sums in f32, f16 and bf16 on the stress inputs and requires the fp16 and bf16 sums to miss by the declared 100x.
  The allowance is the down form's: the sum's error and the bf16 store's rounding (`int4_ref.rows`), the same
  function the existing `down_bf16` entry uses at the same k, so the margins are the ones that entry already proves.

Documented in `docs/kernel-contract.md`: "the head's dense rows to bf16, and the three prompt forms (down to fp32,
down to bf16, gate/up) bit-equal to the plain ones".

## Ask 3: the dense wrapper, decided by its callers

Narrowed to BF16. The evidence, in the order it decided the question:

- `int4.dense` had exactly one caller in the tree: the contract's head entry, which passed `false`
  (`contract_int4.zig`, `.head`). No serving code calls the module yet; `grep -rn "int4.dense"` over `zig/` returns
  that one line.
- Every reader of head output in the engine takes bf16 logits, with no dtype parameter to ask for fp32:
  `sample.draw` ("Row r of bf16 logits drawn ..."), `sample.drawRows`, `sample.logprobRows` ("Each bf16 logits row's
  logprob words"), `sample.topkRows`, and `sample.proposal` refuses a non-bf16 view outright
  (`if (view.dtype != .bf16) return error.ProposalBasisUnsupported`). An fp32 head output would be unusable without
  a conversion kernel that does not exist.
- The contract's head entry is `out = .bf16`, and `docs/kernel-contract.md` describes the head as dense rows to
  bf16; there was no documented fp32 dense form to test.
- The fp32 instantiation the flag could reach is the routed down's `int4_kernel<..., 1, 0, ...>`, which stays
  registered and is gated by the `down_f32` entry; narrowing the wrapper removes a mode, not a compiled kernel.

So `dense` now takes no `f32_out`, always launches the bf16 epilogue, and its doc comment says so.

## Ask 4: a real `int4-contract` dispatch

Why the receipt read zero: `tf-cuda-test kernel-contract WORD...` selects entries of the *registered* fixture list,
and no int4 kernel is registered there (the family's suite is a standalone `contract_int4.run` that the full run
calls from `contract_after.zig`). A filtered run over the word therefore gated no kernel, whatever it printed.

What is now committed:

- `zig/tests/cuda/main.zig`: `if (std.mem.eql(u8, cmd, "int4-contract")) return @import("contract_int4.zig").run(gpu);`
- `zig/tests/cuda/main_usage.zig`: the usage line `int4-contract  the GPTQ int4 experts and head through gates 1-4,
  both controls red (every form built)`.
- `zig/build/kernel_contract.zig`: the build step, the same shape as the other family steps in `cuda()`:
  `const int4 = b.addRunArtifact(runner); int4.addArg("int4-contract");
  b.step("int4-contract", "GPTQ int4 routed experts and head through gates 1-4 on this GPU, both controls red")`.
- `docs/kernel-contract.md`: the command, in "Running it", and the coverage sentence above.

The suite's summary count is not guessed either: `Set.init` builds one `Fixture` and appends one `g.Kernel` per
`entries` element, and `gates.runAll` counts a control in `controls` and every other kernel in `kernels`, so the line
reads `8 kernels` and `2 controls` on this list. The rebased tree's entry list was counted mechanically (`awk` over
`pub const entries`): 10 lines, 2 of them `control:`.

## Planted controls

The family has two, both unchanged by this lane and both compiled into `fatbin_contract_controls` by the `-Dnvcc`
leg:

| control | gate it must fail | how |
|---|---|---|
| `control: int4 routed down with each group's sum rounded to bf16` | gate 4 (`sums`) | `tf_ctl_int4_bf16_sums` rounds each group's sum to bf16 before its scale |
| `control: int4 lm head with each word's nibbles unshuffled` | gate 3 (`shapes`) | the head's words packed as stored, which reads nibble i as input 2i |

Gate 5 has its own two planted controls in the registry (`control: past its bounds`, `control: heavy at 1,024
threads`), and the Paperclip limits audit runs them.

## Gates

## Gates

Run in this lane, on the laptop, with Python and git only (no compiler):

| check | command | result |
|---|---|---|
| lean, base versus head, both trees' own checker | `python tools/pr_check.py --base 7bd7081e0 --pr 4183` | `lean 165 vs 165, 0 new`; 0 errors, 1 advisory warning (no Unreleased CHANGELOG bullet naming #4183) |
| whitespace | `git diff --check origin/main` | clean |
| author and committer | `git log --format=... origin/main..HEAD` | `BadAd84` both, six commits, each signed `G` |
| shared CUDA primitives | `python3 tools/zig/cuda_common_check.py` | `cuda common: 55 local copies, 0 violations`; main: the same 55 and 0 |
| shared CUDA fragments | `python3 tools/zig/cuda_fragment_check.py` | `cuda fragments: 2 fragments, 15 includes, 0 misses` |
| that checker's own tests | `python3 -m unittest discover -s tools/zig -p cuda_common_check_test.py` | `Ran 9 tests ... OK` |
| dependent-launch fixtures | `python3 tools/test_pdl_early_loads.py` | 17 tests, 2 errors, the same two on main (`test_empty_dump_fails`, `test_failed_tool_fails`): inherited, host-specific |
| tree identity | `python3 tools/verify_tree.py in/head.lstree <extracted head>` | 13,489 files, 0 mismatches, 0 extras; the archive's sha256 on the box equals the laptop's |
| pin regeneration guard | `python tools/repin.py tree in/pins-main.tsv` | 167 rows already main's bytes, the 2 named rows re-pinned, no other drift |

Queued on Paperclip but not yet run: the host lock (`~/work/host.lock`) is held by the RoGates3 lane, whose run started
about 08:35 and holds a six hour window. The gate script was submitted at 10:34 and is detached on the box, so it
executes the whole list by itself the moment the lock frees and writes `out/gates.tsv`, one row per gate with its rc,
wall time and summary line, plus `out/GATE-RESULT` (PASS or FAIL) when done:

| gate | command (all under `flock`, `umask 022`) | state |
|---|---|---|
| fmt | `zig fmt --check build.zig zig` | queued |
| pincheck | `python3 in/pincheck.py <head>/` | queued |
| env | `zig build -Dfixed-cpu test-environment-host` | queued |
| serving | `zig build -Dfixed-cpu test-gradient-serving` | queued |
| qwen-serving | `zig build -Dfixed-cpu test-qwen-serving-host` | queued |
| int4-host | `zig build -Dfixed-cpu test-int4-host` | queued |
| cuda-host | `zig build -Dfixed-cpu test-cuda-host` | queued |
| contract-host | `zig build -Dfixed-cpu test-kernel-contract` | queued |
| cfg-aarch64 | `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | queued |
| ct-plain | `zig build compile-cuda-tests` | queued |
| ct-aarch64 | `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | queued |
| ct-nvcc | `zig build -Dnvcc=<13.3> compile-cuda-tests` | queued |
| ct-nvcc-aarch64 | `zig build -Dnvcc=<13.3> -Dtarget=aarch64-linux-gnu compile-cuda-tests` | queued |
| engine | `zig build -Dnvcc=<13.3> -Doptimize=fast -Dsm=121 fatbins install native` | queued |
| limits-images | `zig build -Dnvcc=<13.3> -Dsm=80,86,89,120,121 fatbins kernel-contract-fatbins compile-cuda-tests` | queued |
| limits audit | `tf-cuda-test kernel-contract-limits zig-out/fatbin` | queued; prints one PASS/RED line a launch an SM, 21 int4 launches on five SMs |
| the verb | `tf-cuda-test` (usage) and `tf-cuda-test int4-contract` | queued; the usage line names the new verb and the verb reaches the suite, stopping at sm_61 |

`work/Int4Respond/BOX-STATE.md` records how to wait for and fetch that table, and what to clean up. The deliverable is
not complete until that table is filled from `out/gates.tsv`; this report says so instead of quoting numbers it does
not have.


## What remains device-side

`contract_int4.run` needs a GPU at sm_80 or above. Paperclip's Quadro P4000 is sm_61, so the box can compile every
image and audit every record from disk but cannot load the int4 image; the four device SUMMARY lines and the two
numerical controls going red are the device window's to produce. The exact commands, in the order the PR skill asks
for them:

```
zig build int4-contract -Dnvcc=/usr/local/cuda/bin/nvcc         # SUMMARY int4: 8 kernels, 8 pass, 0 fail, 0 known; 2 controls: 2 red as planted, 0 missed
zig build kernel-contract -Dnvcc=/usr/local/cuda/bin/nvcc       # the full registry, int4 included through contract_after
zig build fatbins kernel-contract-fatbins -Dnvcc=... -Dsm=80,86,89,120,121
tf-cuda-test kernel-contract-limits zig-out/fatbin              # gate 5, the 21 int4 launches on each recorded SM
```

The first line is the one the maintainer asked for: it prints the complete summary and both controls' results on the
rebased tree. Until a window runs it, the reply states that plainly rather than quoting a receipt from another tree.
