## What this changes

Flash Next on CUDA took its routing width (top-10, so 11 slots a row with the shared expert) and its shared expert's
width (640) from constants. With this change the checkpoint's `config.json` selects one of two supported shapes:
top-10 with a 640-wide shared expert, the only shape main loads, or top-5 with a 1280-wide shared expert. Any other
`num_experts_per_tok` or `shared_expert_intermediate_size` is refused at load by the field's name, as
`cuda_config.zig` refuses other fields today. No weight format changes: a checkpoint main loads gets the default
shape and the same launches. The top-5 checkpoint behind #3368 is GPTQ int4, which this step does not load.

- Issue: Refs #3368 (step 1 of the series agreed there).
- Stacked on: main at `41a72fd2578dfbdd73b25663da78d5fc0047bd95`. The receipt below was measured on main at
  `2ba55ec7d3`; of the 14 commits since, the Flash Next ones touch `cuda_draw_batch.zig` and its test, and the only
  file they share with this change is the changelog's Unreleased section.
- `atc overlap --json`: incomplete (it reached its time and pull-request limits). Of the pull requests it
  test-merged, four conflict: #1879, #1924 and #2279 share only `CHANGELOG.md` with this change (the Unreleased
  section), and #1767's file list shares no file with it. Main has since moved to `cc8f2889e7`; this commit merges
  into it without a conflict (`git merge-tree`).

How the widths reach the code:

- `cuda_widths.zig` (new, 100 lines) holds the supported list and the selection. The kernels already take top-k and
  slots as launch arguments (`route_rows` top-k, `fn_moe_sum`, `fn_hc_writeback`, the expert tiles), so the shape
  lives in data: the pass reads a row's slots from its scratch, which is allocated for the shape
  (`Sizes.slots`, `Sizes.shared`), and the shared expert's width from the layer (its `gate_proj` rows). A
  default-shape checkpoint gets the same integers it got from the constants, so its launches, sums and their order
  are unchanged. This is option (a) of the issue; the receipt below is its evidence on the default path.
- The literal `10, 11` at the write-backs (`cuda_batch.zig`, `cuda_batch_hc.zig`) now come from the scratch;
  `cuda_prompt_step.zig`'s row path, which serves the MLX checkpoint only, names the default constants instead.
- **The MTP layer** routes at the main layers' top-k: `config.json` has no routing width for it, its router has the
  same 512 experts, and the shared verify and draft passes lay a row out at one slot count. Since a draft is only a
  proposal, this width moves acceptance, never a reply. Its shared expert's width is its own tensor's: the main
  layers' width or the routed width (640); anything else stops the head's load naming
  `mtp.layers.0.mlp.shared_expert.gate_proj` and its rows.
- **A main layer** whose shared expert's rows differ from `shared_expert_intermediate_size` stops the load naming the
  layer and both numbers; a shared expert outside the supported widths stops it naming its tensor.
- **Captured kernel sets** stay at top-10: their `_topk_rows` is built with `TOPK 10` and `SLOTS 11`
  (`cuda_launch.zig`). A checkpoint of another shape with a captured set is refused at load naming
  `num_experts_per_tok` (`FlashNextWidthsOnCapturedGlue`), and `Tri.topkMany` refuses a captured launch at another
  width.
- **The MLX 4-bit path** (`cuda_moe.zig` and the legacy experts) stays at the default shape; an MLX config of
  another shape is refused naming `num_experts_per_tok`.
- **The two-rank exchange** (`cuda_moe_exchange.zig`): its reduce-scatter size is `h * s.slots * dims` instead of
  `h * slots * dims`. In `cuda_moe_native.zig` the rows cleared before the expert launches and the up projections'
  row layout read the same count, and the shared split's column copies take the layer's width. For the default
  shape these are the same integers, so the exchange is unchanged; I have not run two ranks, which you offered to
  check on your side.
- The two device tests that build a pass of their own (`flashnext_exchange_tests.zig`,
  `flashnext_fp8_experts_tests.zig`) and two host-test fakes pass the default slot count and width.
- `cuda_launch.zig` grows by one line (564); the width plumbing is in its own file.

## Checks on this head

- Head commit: `5cc8b6ace6478771a92087c396239abea870df46` (one commit on main at `41a72fd257`).
- Lean checker, `python3 tools/zig/lean_check.py`, on the base and on this head (the head's checker in both trees):
  base 6,494 files, 341 problems; head 6,495 files, 341 problems; `lean_new.py`: 0 new. (The one inherited finding
  printed is `tools/zig/reuse_served.py:265`.)
- `python3 tools/pr_check.py --base origin/main` on this head: 24 changed files, lean 341 against 341, 0 new;
  0 errors, 1 warning (no `--pr` yet; the Unreleased bullet names #3368 and will name this pull request).
- `zig fmt --check build.zig zig`: clean. `git diff --check`: clean.
- `zig build compile-config-server -Dtarget=aarch64-linux-gnu` and `zig build compile-cuda-tests
  -Dtarget=aarch64-linux-gnu`: both pass.
- Tests run, as the no-GPU workflow runs them, on fresh trees of main (`41a72fd257`) and of this head, each in an
  Ubuntu 24.04 x86_64 container (16 CPUs, Zig 0.17.0, `-j6 --maxrss 6000000000`):

  | Command | main | this head |
  |---|---|---|
  | `zig build -Dfixed-cpu test-host --test-timeout 20m` | 19,145 of 19,285 passed, 140 skipped; 1 step failed (below) | 19,160 of 19,300 passed, 140 skipped; the same step failed |
  | `zig build -Dfixed-cpu test-golden` | | 5 of 5 steps |
  | `zig build -Dfixed-cpu test-kernel-contract` | | 205 of 205 passed |
  | `zig build -Dfixed-cpu fuzz-cortheon` | | 22 of 22 passed |
  | `zig build -Dfixed-cpu test --test-timeout 10m` | | 397 of 410 passed, 13 skipped |
  | `zig build test-cuda-host` | | 6,729 of 6,769 passed, 40 skipped |
  | `zig build test-environment-host` | | 3 of 3 steps |

  The step that failed on both trees is `test-video-layout-linux`: its `tools/zig/test_tfvideo_layout.py` calls `cc`,
  which that container did not have. With gcc 13.3 installed, `zig build -Dfixed-cpu test-video-layout-linux` passes
  on both (3 of 3 steps). The change adds six tests; `test-host` counts 15 more on this head than on main, all passing.
- New tests, each shown failing on a mutant of this change: the mutant applied to this head in a fresh tree, then
  `zig build test-cuda-host` (Ubuntu 24.04 x86_64 container, Zig 0.17.0). Every mutant fails:

  | Mutant | What fails |
  |---|---|
  | the supported list holds the default only | the build: `cuda_widths.zig`'s tests index the top-5 entry |
  | the selection matches top-k 10 only (main's behaviour) | `a top-5 config with a 1280-wide shared expert selects that shape, and the MLX path refuses it by name`, `a width outside the supported list is refused by its field's name`, `the default shape is the constants' and a top-5 checkpoint selects a 1280-wide shared expert` |
  | the MLX path accepts any shape | `a top-5 config with a 1280-wide shared expert selects that shape, and the MLX path refuses it by name` |
  | the scratch sizes the shared buffers by the constant 640 | `the scratch is sized by the shape: a wider shared expert's three buffers, fewer slots' pairs` |
  | the MTP layer accepts any shared width | `the MTP layer routes at the main layers' top-k with its own shared width, and another width is refused` |
  | a captured kernel set serves any shape | `a captured kernel set serves the default shape only` |
- CI: not run (no pull request yet).
- Not run, and why: two ranks (no second GPU here; you offered the device check for this step). I did not build a
  synthetic top-5 checkpoint for a device run; the top-5 shape is exercised in the host tests through the
  selection, the scratch sizing and the refusals.

## Receipt

- Main against branch: one machine, one fresh boot an arm, alternating main, branch, branch, main (M1 B1 B2 M2).
  Each arm runs `tools/bench_concurrent.py --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 0`
  and `tools/bench_openai.py --tokens 256 --reps 3 --temperatures 0`, both from main's `tools/`. A cell counts as
  slower when both branch runs are under both main runs and the mean gap is over 1%. No cell is slower:

  | prompt | streams | M1 | B1 | B2 | M2 | branch against main | slower? |
  |---|---|---|---|---|---|---|---|
  | code | 1 | 72.6 | 72.7 | 72.4 | 72.7 | -0.14% | no |
  | code | 2 | 69.7 | 69.7 | 69.8 | 69.8 | +0.00% | no |
  | code | 4 | 62.5 | 62.3 | 62.3 | 62.2 | -0.08% | no |
  | chat | 1 | 46.7 | 46.6 | 46.6 | 46.5 | +0.00% | no |
  | chat | 2 | 43.6 | 43.6 | 43.5 | 43.5 | +0.00% | no |
  | chat | 4 | 39.8 | 39.6 | 39.5 | 39.5 | -0.25% | no |

  (per-stream decode tok/s, `bench_concurrent`). Accepted drafts per round are the same in all four arms, to the
  count: 7,934 accepted of 11,682 drafted over 3,827 rounds in `bench_concurrent` (2.073 a round), and 1,488 of
  2,384 over 552 rounds in `bench_openai` (2.696 a round), from `/metrics` before and after each run.
- Boxes it reaches: Flash Next on CUDA (one GPU and two ranks); the MLX path only through its refusal.
- New switch? None. The config decides.
- Environment: TensorFold `2ba55ec7d3` (main) and this head, each built into an image on the same base (the first 71
  layers equal; CUDA 13.3.1); NVIDIA GB10 (DGX Spark), driver 580.178.04, Ubuntu 24.04.5, kernel
  7.0.0-1019-nvidia-64k; checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at revision
  `b9ce18a6887e18c089fdea8509a33e63429a3300`, bf16 KV, a 131,072-token window, `--parallel 4`. No MLX 4-bit
  checkpoint is on this box.
- Paths and platforms the change reaches, which I ran and which I could not: one GPU on GB10 run; two ranks not run.
- Exactness: main and this branch each pass every check, each on its own fresh boots (the prompt cache on, and off
  for the fresh side), on the same images as the speed receipt:
  - drafted equals `"draft": false`: `bench_concurrent --serial` 2 of 2 greedy, 8 of 8 at temperature 1.0 and 6 of 6
    over the six golden prompts; eight prompts sent with drafts on and with `"draft": false`, token ids equal 8 of 8
    with the prompt cache on and 8 of 8 with it off.
  - a resumed prompt equals a fresh one: 7 of 7 multi-turn replies resumed from the prompt cache equal the same
    requests sent fresh to a boot with the cache off.
  - concurrent equals solo: `bench_concurrent --alone` 42 of 42 greedy and 42 of 42 at temperature 1.0 (code and
    chat at 1, 2 and 4 streams), and 13 of 13 over six distinct golden prompts at 1, 2, 4 and 6 streams.
  - The branch's replies equal main's for the same request and boot kind: `bench_concurrent` token hashes 16 of 16
    and 6 of 6 (golden), drafted and plain token ids 8 of 8 with the cache on and 8 of 8 with it off, and the
    multi-turn first and resumed replies 7 of 7 each. In the speed receipt, B1, B2 and M2 match M1's token hashes 8
    of 8.
- Main against this branch, same machine and checkpoint: as above.
- Decode speed before and after, from `tools/bench_openai.py` (median decode tok/s of 3):

  | prompt | M1 | B1 | B2 | M2 | branch against main | slower? |
  |---|---|---|---|---|---|---|
  | fibonacci-raw | 72.44 | 72.45 | 72.36 | 72.22 | +0.10% | no |
  | gpu-chat-no-think | 46.68 | 46.53 | 46.48 | 46.49 | -0.18% | no |

- Memory: each boot's own budget line is the same in all four arms (model 72.73 GiB; 4 streams, 4.11 GiB each at a
  131,072-token window, of 28.0 GiB left after a 9.0 GiB reserve). The prompt cache that fills the rest is 11.5 GiB on
  M1 and 11.6 GiB on B1, B2 and M2. The container's resident memory after boot (`docker stats`) is 4.07, 4.067, 4.066
  and 4.046 GiB.
- Prompt speed before and after: the same images and machine, M1 B1 B2 M2 again, each a fresh boot with
  `--prompt-cache-gib 0`. Cold prompts of 2k to 64k tokens (a fresh salt first, thinking off, median of 3), and the
  first request of `tools/bench_cache.py --require-cold` (its 2,571-token prompt, 0 cached tokens in every arm). Same
  noise rule, with slower meaning longer. No cell is slower:

  | prompt | M1 | B1 | B2 | M2 | branch against main | slower? |
  |---|---|---|---|---|---|---|
  | cold 2k, time to first token (s) | 1.069 | 1.051 | 1.082 | 1.073 | -0.42% | no |
  | cold 8k | 4.038 | 3.983 | 4.017 | 4.005 | -0.53% | no |
  | cold 32k | 16.054 | 15.925 | 16.153 | 16.066 | -0.13% | no |
  | cold 64k | 33.060 | 32.828 | 33.156 | 33.098 | -0.26% | no |
  | `bench_cache --require-cold`, first `ttft_s` | 1.225 | 1.223 | 1.226 | 1.227 | -0.12% | no |

- Licence of any new weights or drafter: n/a.

## Checklist

- [x] The title and description match the head commit, including the receipt and the stack.
- [x] New tests fail before the change, pass after it, and skip cleanly without their dependency.
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits. No AI attribution lines.
- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [x] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo.
- [x] No precision traded for speed. If the bits change, the description says which sums change and why.
- [x] Decode and prompt processing are no slower than main at one stream and the widest admitted.
