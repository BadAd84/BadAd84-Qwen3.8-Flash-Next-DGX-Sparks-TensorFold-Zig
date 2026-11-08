Lever 1 upstream PR package - DRAFT body (pre-restyle). Internal notes, not part of the PR.
TEMPLATE for the 64-row-default variant: fill every [64ROW] from the re-measured receipt (both arms on the
64-row default, same tip), then re-present. Do not post until the 64-row verdict (Rows64on124) is in and the owner
approves the default-on framing.
Branch: port-copy-windows, code commit 71f1afaee on ab4b2f05 (upstream main tip 2026-11-07, git ls-remote).
Receipt commit sha + final head filled after the receipt lands.
Arms: upab4 (ab4b2f05 stock) and cwab4 (71f1afaee, the port) - BOTH built from the same tip ab4b2f05 with `fatbins native`
(embeds ab4b2f05's own engine kernels; the serve binaries differ from each other and from the 267c5af6 build).
[AB4B] = fill from the ab4b2f05 receipt run (runsR + rsum.py).
---
Title: [64ROW title: state the 64-row default and the resync together, or split the two PRs per the verdict]

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
- Stacked on: main.
- Overlap: run as a file-level intersection against all 181 open PRs (the git protocol, not the REST API). Core
  logic in `proposer.zig` and `windows.zig` is clear of live overlap; `proposer.zig` is hit by #2373 only, whose
  merge base is 6,960 commits behind main and predates the lanes split, so that one hit is a stale whole-file
  artifact. One same-function overlap to sequence: #1394 (Llama2), a decode-time copy proposer, runs on CUDA/GB10.
- Not run: Metal, HIP and XPU host tests (this box is CUDA only), and any GPU kernel contract (no kernel changes).

## Checks on this head

- Head commit: `71f1afaee` (code), plus the receipt commit that adds `docs/receipts/flashnext-copy-resync/`.
- Lean checker, `python3 tools/zig/lean_check.py`, each tree with its own copy: base `[64ROW base tip]` [64ROW base files] files / [64ROW base problems] problems, this head [64ROW head files] files / [64ROW head problems] problems, [64ROW new count] new.
- Tests: `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU, no network. [64ROW host suite: base vs head step counts, the failing-test lists compared, the added-test count]viceLost` under `--network none` with no GPU; the stable signal is the identical failure set.
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

- Environment: both arms built from the same tip, upstream main `ab4b2f05` (2026-11-07). `[64ROW stock arm]` is `[64ROW tip]` stock; `[64ROW port arm]` is this change (`[64ROW head sha]`), built on the 64-row default. Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuses `--kv-cache fp8`), 131,072-token windows, `--parallel 6`. Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`).
- Levels: [64ROW levels]; the memory line re-measured with the 64-row scratch ([64ROW memory numbers]; 8 streams [64ROW fits or the refusal numbers]).
- Paths the change reaches: the decode-time copy proposer in `core/lanes`. Ran on CUDA/GB10; did not run Metal, HIP or XPU.
- Exactness, same checkpoint and settings:
  - Golden 6/6 identical: every `cwab4` reply equals stock `upab4`'s own reply on every cell.
  - `tools/bench_concurrent.py --alone --serial`: 0 failed and 0 unmeasured requests at every level on both arms; the reply-level equality is the golden comparison and the workload hashes below.
  - Every rewrite and edit reply hash is equal between the two arms.
- Main against this branch, same machine and checkpoint, the lever's own workloads (medians of all runs, two boots an arm, `upab4` / `cwab4` tok/s):

  | workload | upab4 / cwab4 | change |
  |---|---|---|
  | one-word rewrite (1 stream) | [64ROW stock / port] | [64ROW change] |
  | two concurrent edits, 1st / 2nd | [64ROW stock / port] | [64ROW change] |
  | edit beside a prose reply, edit / prose | [64ROW stock / port] | [64ROW change] |
  | verbatim copy (1 stream) | [64ROW stock / port] | [64ROW change] |

Verbatim copy does not move, which is expected: upstream already ramps a lone copy to `max_copy` 31, so `jump`
only shortens the climb and an 1,800-token copy amortises it away. The win is on the edit workloads, where the
source survives the mismatch.
- Decode speed before and after, `tools/bench_openai.py` one request at a time, greedy: [64ROW bench_openai line: code and gpu-chat, two passes an arm, the plain-decode bound stated as measured]
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
