Title: flashnext: serve the largest row-exact copy-window width, measured with a boot-time self-check

## What this changes
  *   Flash Next's copy windows are hard capped at `exact_width` (32 rows), the widest width upstream proven to
reproduce one-token steps bit for bit. Rows past that aren't claimed - there is no point serving a window
wider than the proven prefix.

This change lifts the served window max and adds a boot-time self-check that measures the row-invariance
boundary on the real weights: it sweeps every width to `max_rows` over a synthetic prompt and serves the
largest prefix whose every row is byte-equal to its one-token step. On the NVFP4 checkpoint, this boundary is
48 rows (width 49 differs, `batch.late_rows`), so the engine serves 48-row copy windows and logs
the fallback line - if any shape ever fails, it falls back to upstream's 32 row windows. Worst case is exactly today's
behaviour; `TF_FLASHNEXT_WINDOW_CHECK=0` skips the probe.

  *   Issue: n/a. This changes which tokens get proposed as drafts, and never the math. A draft is still only accepted when it equals the plain token.
  *   Stacked on: main.
  *   Overlap: `atc overlap --json` on this head: 13 changed files, 142 open PRs share at least one of
them, and 9 hard merge conflicts - every one is `CHANGELOG.md`, the ordinary case; no code file conflicts.
One same-function change to sequence: #1394 (Llama2), a decode-time copy proposer on CUDA/GB10. The board
snapshot is partial (`pullFilesLimit`), so 132 PRs' conflicts are unknown.

## Checks on this head
  *   Head commit: `93475cf7e` (the receipt; beneath it `68761ba11a` carries the CHANGELOG bullet and the two
comment-length fixes, and the measured image `tensorfold-qwen38:w64` was built from `8a83b6352`, which
differs from the head only by comments, the CHANGELOG bullet and the receipt files). The receipt adds
`docs/receipts/flashnext-window-rows/`.
  *   `tools/pr_check.py --base origin/main` (upstream's own gate): 0 errors, 0 warnings, 8 changed files, lean 116 vs 116, 0 new. `zig fmt --check` clean on every touched file.
        *    Tests: `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU and no network. Base and head build the same steps with the identical failing-test list (the 3 pre existing environment tests - a listener test needing a network and the two `drama_voice_tool` cleanup tests expecting `error.AccessDenied` as root) and equal per-test pass counts. The two layout-test pinning changes in the diff re-derive the scores/saved-projection/n-gram terms from `max_rows` (the totals they pin come from the suite's own measured values at 64 rows).
  *   CI: not run here and the gates above are the local equivalents.

## Receipt
  *       A full receipt can be found in `docs/receipts/flashnext-window-rows/` (README, the two bench tools' output on both arms, the rewrite workloads and SHA256SUMS)
    *   Which boxes it reaches: one NVIDIA  GB10 (DGX Spark) class, CUDA, the NVFP4 checkpoint
    *   This change adds no settings, the boot self-check is always "on" and makes the fallback automatic; `TF_FLASHNEXT_WINDOW_CHECK=0` skips the probe (not recommended outside bring-up).
      *   The copy resync, ramp and shared round rules are a separate change and don't ride here.
    *   Environment: both arms built from the same tip - upstream `267c5af6a`. `up124` is `267c5af6a` stock; `w64` is this change, built `--no-cache` from the branch at `8a83b6352` (head minus 2 comment fixes). Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuses `--kv-cache fp8`), 131072 token windows, `--parallel 6`. Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`)
    *   Levels are 1, 2, 4 and 6. Device scratch grows 0.05 GiB per live drafting stream (4.11 -> 4.16 at 2-6 streams, observed on the boot lines) no level refuses at 131072 tokens. 8 streams is not run - the stock arm cannot serve it at bf16 KV (32.86 GiB of cache against 31.41 free).
    *   Paths the change reaches: the decode-time copy proposer in `core/lanes`. Ran on CUDA/GB10, did not run Metal, Hip or XPU.
    *   Exactness, same checkpoint and settings:
      *    Golden 6/6 Identical:
              every `w64` reply equals stocks own reply on all cells
      *    tools/bench_concurrent.py --alone --serial
            : 0 failed and 0 unmeasured requests at all levels, both arms the reply level equality is the golden comparison and the workload hashes below
      *   Every copy, rewrite and edit reply hash is equal between both arms (1 distinct sha per (streams, kind); One harness side probe crash on a single cell, its w64 value equals up124's own at 2/4 streams).
        *   Main against this branch, same machine and checkpoint the levers own workloads (boot split medians of all runs, 2 boots an arm at 1/2 streams) `up124` / `w64` tok/s:
          | workload | up124 / w64 | change |
          |---|---|---|
          |   one word rewrite (1 stream) | 228.8 / 256.7 | +12.2%|
          |   2 concurrent edits, 1st / 2nd | 141.1 / 137.7, 141.3/ 138.6 | -2.4% /-1.9% (inside the boot spread, decode path is identical between arms) |
          |   edit beside a prose reply, edit / prose | 147.7 / 147.8, 47.4/ 47.4 |      0.0%|
          |   verbatim copy (1 stream)     | 374.3 / 473.7   | +26.6%|
        *   Verbatim copy does not move, which is expected - upstream already ramps a lone copy to `max_copy` 31, so `jump`
    only shortens the climb and a 1800 token copy amortises it away. The win is on the edit workloads where the
source survives the mismatch.
        *   Decode speed before and after, the maintainer's tools, on the final head, one request at a time greedy:
          `tools/bench_openai.py` 256 tokens, 2 passes an arm - code 73.8 / 73.4 stock against 72.9 / 72.9 port,
    gpu-chat 47.2 / 47.2 against 46.8 / 46.8 and
    `tools/bench_concurrent.py --alone --serial` (code, aggregate tok/s):
           s1: 73.4 / 72.8
    s2: 72.8 / 72.1
    s4: 72.2 / 71.8
    s6: 72.1 / 71.7 - every cell within 0.9%
  *   The boot split cell medians agree:
           1 stream per stream prose: 51.9 / 51.9
    code:72.8/72.3 - (2 boots an arm) and every 4/6 stream boot median within 1.5% of the stock.
  *   Prompt speed before and after n/a The change is in the decode time copy proposer, which does not reach prompt
processing.
    *   Licence: n/a, no new weights or drafter.

## The boundary, stated
  the 64 row window isn't here on purpose - `exact_width` is the widest window that produces one token steps bit
for bit and upstream set it at 32 (`5bb64597d`, which already ramps a lone copy from 15 to 31 drafts and keeps
the row counts past the kernels 64 row switch untouched). Raising `mtp.max_rows` to 64 is a kernel row invariance
claim + a device scratch change. This PR carries that receipt, the boot time self check measured the boundary
on the real weights -
     widths 1-48 are byte equal to their one token steps at every row, width 49 is the first that differs - so
the engine serves 48 row windows and falls back to upstream's 32 whenever any row differs, with
    `TF_FLASHNEXT_WINDOW_CHECK=0` as the skip. The 64 row window itself isn't claimed on this checkpoint.

## Checklist:
  *   [x] Title/description matches head commit (including receipt and the stack)
  *   [x] New tests fail pre change and pass post it and cleanly skip without its dependency (4 faithful mutants, each died by its named test - the prompt only arming gate, miss arming and shared round ramp + width).
  *   [x] Comments and docstrings are one-liners; no measurements or history in the source.
  *   [x] No personal data, machine names, internal hosts or local paths in the diff or its commits; no AI attribution lines.
  *   [x] Every token still goes through the lane rounds (no serial path, nothing that needs drafts off)
  *   [x] Drafted output = "draft": false and resumed prompt == fresh one and concurrent == solo.
  *   [x] No precision for speed. The change is selecting which tokens are proposed as drafts - it changes no sum.
  *   [x] Decode + Prompt processing is no slower than main at 1 stream and the widest admitted. With the copy policy on, the edit
workloads are faster and plain decode is just noise.
