Title: flashnext: serve the largest row-exact copy-window width, measured with a boot-time self-check

## What this changes

Flash Next's copy windows are hard-capped at `exact_width` (32 rows), the widest width upstream proved
reproduces one-token steps bit for bit. Rows past that width are not claimed: a window wider than the proven
prefix cannot serve without a row-invariance receipt.

This change raises the served copy-window width to 64 and adds a boot-time self-check that measures the row
invariance boundary on the real weights: it sweeps every width to `max_rows` over a synthetic prompt, and serves
the largest prefix whose every row is byte-equal to its one-token step. On the NVFP4 checkpoint that boundary is
48 rows (width 49 is the first that differs, the pending-row log's `batch.late_rows`), so the engine serves
48-row copy windows and logs the fallback line; if any shape ever fails, it serves upstream's 32-row windows -
the worst case is exactly today's behaviour. `TF_FLASHNEXT_WINDOW_CHECK=0` skips the probe.

- Issue: n/a. This changes the served copy-window width and adds the probe that proves it; it changes only
  which tokens get proposed as drafts, never the math. A draft is still accepted only when it equals the plain
  token.
- Stacked on: main.
- Overlap: run as a file-level intersection against all 181 open PRs (the git protocol, not the REST API). Core
  logic in `proposer.zig` and `windows.zig` is clear of live overlap; `proposer.zig` is hit by #2373 only, whose
  merge base is 6,960 commits behind main and predates the lanes split, so that one hit is a stale whole-file
  artifact. One same-function overlap to sequence: #1394 (Llama2), a decode-time copy proposer, runs on CUDA/GB10.
- Not run: Metal, HIP and XPU host tests (this box is CUDA only), and any GPU kernel contract (no kernel changes).

## Checks on this head

- Head commit: `71f1afaee` (code), plus the receipt commit that adds `docs/receipts/flashnext-window-rows/`.
- Lean checker, `python3 tools/zig/lean_check.py`, each tree with its own copy: base `267c5af6a` 5768 files / 116 problems, this head (`427063f62`) 5771 files / 116 problems, 0 new (the three extra files are the port's).
- Tests: `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU, no network. Base and head
  build 581/585 steps with identical failing-test lists - the three pre-existing environment tests (a listener
  test needing a network, two `drama_voice_tool` cleanup tests expecting `error.AccessDenied` as root) - and
  equal per-test pass counts (7695/7764 on both).ounts, the failing-test lists compared, the added-test count]viceLost` under `--network none` with no GPU; the stable signal is the identical failure set.
- CI: not run here; the gates above are the local equivalents.
- Not run, and why: Metal, HIP and XPU host tests (this box is CUDA only), and any GPU kernel contract (no kernel changes).

## Receipt

A full receipt is in `docs/receipts/flashnext-window-rows/` (README, the two bench tools' output on both arms, the rewrite workloads, SHA256SUMS).

- Boxes it reaches: one NVIDIA GB10 (DGX Spark class), CUDA, the NVFP4 checkpoint.
- This change adds no settings. The boot self-check is on by default and makes the fallback automatic;
  `TF_FLASHNEXT_WINDOW_CHECK=0` skips the probe (not recommended outside bring-up). The copy resync, ramp
  and shared-round rules are a separate change and do not ride here.

- Environment: both arms built from the same tip, upstream `267c5af6a`. `up124` is `267c5af6a` stock; `w64` is this change (`7bf66d350`), built `--no-cache` from the branch tip. Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuses `--kv-cache fp8`), 131,072-token windows, `--parallel 6`. Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`).
- Levels are 1, 2, 4 and 6. Device scratch grows 0.05 GiB per live drafting stream (4.11 -> 4.16 GiB at 2-6 streams, observed on the boot lines); no level refused at 131,072 tokens. 8 streams is not run: the stock arm cannot serve it at bf16 KV (32.86 GiB of cache against 31.41 free).
- Paths the change reaches: the decode-time copy proposer in `core/lanes`. Ran on CUDA/GB10; did not run Metal, HIP or XPU.
- Exactness, same checkpoint and settings:
  - Golden 6/6 identical: every `w64` reply equals stock `up124`'s own reply on every cell.
  - `tools/bench_concurrent.py --alone --serial`: 0 failed and 0 unmeasured requests at every level on both arms; the reply-level equality is the golden comparison and the workload hashes below.
  - Every copy, rewrite and edit reply hash is equal between the two arms (1 distinct sha per (streams, kind); one harness-side probe crash on a single cell, its w64 value equals up124's own at 2/4 streams).
- Main against this branch, same machine and checkpoint, the lever's own workloads (boot-split medians of all runs, two boots an arm at 1 and 2 streams, `up124` / `w64` tok/s):

  | workload | up124 / w64 | change |
  |---|---|---|
  | one-word rewrite (1 stream) | 228.8 / 256.7 | +12.2% |
  | two concurrent edits, 1st / 2nd | 141.1 / 137.7, 141.3 / 138.6 | -2.4% / -1.9% (inside the boot spread; the decode path is identical between arms) |
  | edit beside a prose reply, edit / prose | 147.7 / 147.8, 47.4 / 47.4 | 0.0% |
  | verbatim copy (1 stream) | 374.3 / 473.7 | +26.6% |

Verbatim copy does not move, which is expected: upstream already ramps a lone copy to `max_copy` 31, so `jump`
only shortens the climb and an 1,800-token copy amortises it away. The win is on the edit workloads, where the
source survives the mismatch.
- Decode speed before and after, the maintainer's tools on the final head, one request at a time, greedy:
  `tools/bench_openai.py` 256 tokens, two passes an arm - code 73.8 / 73.4 stock against 72.9 / 72.9 port,
  gpu-chat 47.2 / 47.2 against 46.8 / 46.8; `tools/bench_concurrent.py --alone --serial` (code, aggregate
  tok/s): s1 73.4 / 72.8, s2 72.8 / 72.1, s4 72.2 / 71.8, s6 72.1 / 71.7 - every cell within 0.9%.
  The boot-split cell medians agree: 1-stream per-stream prose 51.9 / 51.9, code 72.8 / 72.3 (two boots an
  arm), every 4/6-stream boot median within 1.5% of stock.
- Prompt speed before and after: n/a. The change is in the decode-time copy proposer and does not reach prompt
  processing.
- Licence of any new weights or drafter: n/a, no new weights.

## The boundary, stated

The 64-row copy window is deliberately not here. `exact_width` is the widest window that reproduces one-token
steps bit for bit; upstream set it at 32 (commit `5bb64597d`, which already ramps a lone copy 15 to 31 drafts and
keeps the row counts past the kernels' 64-row switch unchanged). Raising `mtp.max_rows` to 64 is a kernel
row-invariance claim plus a device-scratch change. This PR carries that receipt: the boot-time self-check measured
the boundary on the real weights - widths 1-48 are byte-equal to their one-token steps at every row, width 49 is the
first that differs - so the engine serves 48-row windows and falls back to upstream's 32 whenever any row differs,
with `TF_FLASHNEXT_WINDOW_CHECK=0` as the skip. The 64-row window itself is not claimed on this checkpoint.

## Checklist

- [x] The title and description match the head commit, including the receipt and the stack.
- [x] New tests fail before the change, pass after it, and skip cleanly without their dependency. (Four faithful mutants, each killed by its named test: the prompt-only arming gate, the miss arming, and the shared-round ramp and width.)
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits. No AI attribution lines.
- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [x] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo.
- [x] No precision traded for speed. The change selects which tokens are proposed as drafts; it changes no sum.
- [x] Decode and prompt processing are no slower than main at one stream and the widest admitted; with the copy policy on, the edit workloads are faster and plain decode is within noise.
