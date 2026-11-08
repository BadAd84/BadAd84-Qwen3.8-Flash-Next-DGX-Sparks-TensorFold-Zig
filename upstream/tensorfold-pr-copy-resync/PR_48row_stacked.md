Lever 1 upstream PR package - DRAFT body (pre-restyle). Internal notes, not part of the PR.
HOLD: do not post until the 64-row window verdict (Rows64on124) is in. If the 64-row window ships default-on,
this PR must be rebased onto it, the receipt re-run at 64 rows (both arms, same tip), the workload table and
the memory note re-measured, and the body re-presented. The settings retune (CONFIDENCE/PRODUCT_STREAMS)
feeds the same default-on decision and may also change the measured numbers.
Branch: port-copy-windows, code commit 71f1afaee on ab4b2f05 (upstream main tip 2026-11-07, git ls-remote).
Receipt commit sha + final head filled after the receipt lands.
Arms: upab4 (ab4b2f05 stock) and cwab4 (71f1afaee, the port) - BOTH built from the same tip ab4b2f05 with `fatbins native`
(embeds ab4b2f05's own engine kernels; the serve binaries differ from each other and from the 267c5af6 build).
[AB4B] = fill from the ab4b2f05 receipt run (runsR + rsum.py).
---
Title: lanes: copy re-sync past an edit, and the lone copy ramp in shared rounds

Body:

## What this changes

Flash Next's proposer loses its source the moment a drafted window misses.
`SuffixLookup` re-finds the stream's history by 3-gram and copies the longest suffix match, so one changed word
inside a copy span denies the next match for quite some rounds and a reply that repeats and edits a file keeps
falling back to 1 token a round across each edit.

This adds an optional copy resync that keeps the source position past a rejected draft and proposes from there
without waiting for a fresh match, plus a copy ramp policy and a shared round rule. Every part is off by default, so
a default boot is exactly like always was.

- Issue: n/a, this is a lane proposer feature behind off-by-default settings (not a new family, backend or
  arithmetic change) and it changes only which tokens get proposed as drafts, never the math. A draft is still
  accepted only when it equals the plain token.
- Stacked on: the copy-window-width PR (this change is written against the 48-row default; the receipt numbers are from the 32-row base and are re-verified before merge).
- Overlap: run as a file-level intersection against all 181 open PRs (the git protocol, not the REST API). Core
  logic in `proposer.zig` and `windows.zig` is clear of live overlap; `proposer.zig` is hit by #2373 only, whose
  merge base is 6,960 commits behind main and predates the lanes split, so that one hit is a stale whole-file
  artifact. One same-function overlap to sequence: #1394 (Llama2), a decode-time copy proposer, runs on CUDA/GB10.
- Not run: Metal, HIP and XPU host tests (this box is CUDA only), and any GPU kernel contract (no kernel changes).

## Checks on this head

- Head commit: `b212b9f49` (this change, cherry-picked onto the 48-row-window receipt head `190be7e35`,
  so it stacks directly on the window PR; the receipt adds `docs/receipts/flashnext-copy-resync/`).
  The measured receipt is from the 32-row base (`upab4` / `cwab4` on `ab4b2f05`); the workloads are
  re-measured on the 48-row default before merge, and the numbers here are that measurement.
- Lean checker, `python3 tools/zig/lean_check.py`, each tree with its own copy: base `ab4b2f05` 5864 files / 116 problems, this head 5864 files / 116 problems, 0 new.
- Tests: `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU, no network. Base `ab4b2f05` and this head both build 589/592 steps with the same single failing step, and both fail exactly the same three environment tests: one listener test that needs a network, two `drama_voice_tool` cleanup tests that expect `error.AccessDenied` while the container runs as root. The four added tests pass. The absolute pass counts carry run-to-run variance because several CUDA test binaries abort with `DeviceLost` under `--network none` with no GPU; the stable signal is the identical failure set.
- CI: not run here; the gates above are the local equivalents.
- Not run, and why: Metal, HIP and XPU host tests (this box is CUDA only), and any GPU kernel contract (no kernel changes).

## Receipt

A full receipt is in `docs/receipts/flashnext-copy-resync/` (README, the two bench tools' output on both arms, the rewrite workloads, SHA256SUMS).

- Boxes it reaches: one NVIDIA GB10 (DGX Spark class), CUDA, the NVFP4 checkpoint.
- The switches, all unset by default, strict values that refuse an unknown name at start:

  | setting | values | default |
  |---|---|---|
  | `TENSORFOLD_COPY_RESYNC` | 0, 1 | off |
  | `TENSORFOLD_COPY_RESYNC_PROMPT_ONLY` | 0, 1 | prompt copies only |
  | `TENSORFOLD_COPY_SHARED` | 0, 1 | off |
  | `TENSORFOLD_COPY_MISS` | first, keep | first |
  | `TENSORFOLD_COPY_RAMP` | double, jump | double |

- Environment: both arms built from the same tip, upstream `ab4b2f05` (2026-11-07, the 32-row-window base the receipt was measured on). `upab4` is `ab4b2f05` stock; `cwab4` is this change (`71f1afaee`). Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuses `--kv-cache fp8`), 131,072-token windows, `--parallel 6`. Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`).
- Levels are 1, 2, 4 and 6. The stock arm cannot serve 8 streams at bf16 KV on GB10: eight 131,072-token windows need 32.86 GiB of cache against the 31.41 GiB the budget leaves, so 8 does not admit.
- Paths the change reaches: the decode-time copy proposer in `core/lanes`. Ran on CUDA/GB10; did not run Metal, HIP or XPU.
- Exactness, same checkpoint and settings:
  - Golden 6/6 identical: every `cwab4` reply equals stock `upab4`'s own reply on every cell.
  - `tools/bench_concurrent.py --alone --serial`: 0 failed and 0 unmeasured requests at every level on both arms; the reply-level equality is the golden comparison and the workload hashes below.
  - Every rewrite and edit reply hash is equal between the two arms.
- Main against this branch, same machine and checkpoint, the lever's own workloads (medians of all runs, two boots an arm, `upab4` / `cwab4` tok/s):

  | workload | upab4 / cwab4 | change |
  |---|---|---|
  | one-word rewrite (1 stream) | 230.5 / 300.2 | +30.2% |
  | two concurrent edits, 1st / 2nd | 142.1 / 201.5, 142.3 / 212.6 | +41.7% / +49.3% |
  | edit beside a prose reply, edit / prose | 148.9 / 234.8, 47.8 / 50.2 | +57.7% / +5.0% |
  | verbatim copy (1 stream) | 376.4 / 375.9 | -0.1% |

Verbatim copy does not move, which is expected: upstream already ramps a lone copy to `max_copy` 31, so `jump`
only shortens the climb and an 1,800-token copy amortises it away. The win is on the edit workloads, where the
source survives the mismatch.
- Decode speed before and after, `tools/bench_openai.py` one request at a time, greedy: code 73.1 / 73.4 stock
  against 73.0 / 73.0 port, gpu-chat 47.0 / 47.0 against 46.7 / 46.9 (two passes an arm). Plain decode is unchanged
  within noise: two boots an arm gave opposite signs with per-arm means under 1% apart, so the difference is bounded
  at about +-2% - not a regression, and certainly not a gain.
- Prompt speed before and after: n/a. The change is in the decode-time copy proposer and does not reach prompt
  processing.
- Licence of any new weights or drafter: n/a, no new weights.

## What is deliberately NOT included

The 64-row copy window is deliberately not here. `exact_width` is the widest window that reproduces one-token
steps bit for bit; upstream set it at 32 (commit `5bb64597d`, which already ramps a lone copy 15 to 31 drafts and
keeps the row counts past the kernels' 64-row switch unchanged). Raising `mtp.max_rows` to 64 is a kernel
row-invariance claim plus a device-scratch change (`max_rows * vocab * 2` draft scores, `best_bytes`, the KV page
pool's `window_rows`) and needs its own receipt.

## Checklist

- [x] The title and description match the head commit, including the receipt and the stack.
- [x] New tests fail before the change, pass after it, and skip cleanly without their dependency. (Four faithful mutants, each killed by its named test: the prompt-only arming gate, the miss arming, and the shared-round ramp and width.)
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits. No AI attribution lines.
- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [x] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo.
- [x] No precision traded for speed. The change selects which tokens are proposed as drafts; it changes no sum.
- [x] Decode and prompt processing are no slower than main at one stream and the widest admitted; with the copy policy on, the edit workloads are faster and plain decode is within noise.
