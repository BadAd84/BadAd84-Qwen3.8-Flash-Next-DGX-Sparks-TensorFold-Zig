Title: flashnext: serve the largest row-exact copy-window width (measured with a boot time self-check)

What this changes:
Flash Next's proposer loses its source the moment a drafted window misses.
SuffixLookup re-finds the stream's history by 3-gram and copies the longest suffix match, so
a "word changed" inside a copy span denies the next match for quite some rounds and a reply that repeats and edits a file keeps falling back to 1 token a
round across each edit.

This adds an optional copy resync that keeps the source position past a rejected draft and proposes from there
without waiting for a fresh match, plus a copy ramp policy and a shared round rule. Everyone is off by default (so a
default boot is just like always was).

- Issue: n/a, this is a lane proposer feature behind off-by-default settings (not a new family/backend/ arithmetic change). But it's just which tokens get proposed as drafts, never the math. i.e. still accept draft only when equals to the plain token.
- Stacked on: main
- Overlap: Run as a file interstion against all 181 open PRs (git protocol, not the rest api). Core logic in `proposer.zig`, `windows.zig` is very clearly free of live overlap (`proposer.zig` only gets hit by #2373, and that merge base is 6960 commits behind main and predated the lanes split). So basically that one hit is a stale whole file artefact. Other same funciton overlap to sequence:
  • #1394 (Llama2) - decode time copy proposer
    * Runs on cuda/gb10 this box is cuda only and any gpu kernel contract (no kernel changes)
- Not run: Metal/HIP/XPU host tests (this box is CUDA only) any GPU kernel

## Checks on this head

- Head commit: `71f1afaee` (code) + the receipt commit that adds `docs/receipts/flashnext-window-rows/`
- Lean checker (`python3 tools/zig/lean_check.py`), each tree with its own copy: base `267c5af6a` 5768 files / 116 problems, this head (`427063f62`) 5771 files / 116 problems, 0 new (the 3 extra files are the port's)
- Tests: `zig build test --summary all` in `nvcr.io/nvidia/pytorch:26.07-py3`, no GPU, no network. Base/Head
   - Build 581/585 steps with identical failing-test lists (the 3 pre-existing env tests - a listener test needing a network and the 2 drama_voice_tool cleanup tests expecting `error.AccessDenied` as root) and equal per-test pass counts (7695/7764 on both)
   - Stable signal of the failing-test lists compared, the added-test count
   - Build 1.2 GB under `--network none` with no GPU; the stable signal is the identical failure set.
- CI: not run here, gates above are local eq
- Not run and why:
   - Metal, HIP and XPU host tests (this box is CUDA only)
   - Any GPU kernel contract (no kernel changes)

## Receipt

A full receipt is in `docs/receipts/flashnext-window-rows/` (README, the 2 bench tools' output on both arms, the rewrite workloads, SHA256SUMS)

- Boxes it reaches:   1x NVIDIA GB10 (DGX Spark class) - CUDA - NVFP4 checkpoint
- This change adds no settings. Boot self check is on by default and makes the fallback automatic;
`TF_FLASHNEXT_WINDOW_CHECK=0` to skip the probe (dont recommend this outside bring up). Copy resync/ramp and shared round rules is a “separate change”, so doesnt ride here.

- Environment: both arms built from the same tip, upstream `267c5af6a`. `up124` is that stock (267c5af6a), w64 is this change (`7bf66d350`), built `--no-cache` from br head. Zig 0.17.0, nvcc for sm_121, NVIDIA GB10, driver 580.178.04, vision off, bf16 KV (Flash Next refuse `--kv-cache fp8`), 131,072-token windows, `--parallel 6`
 Checkpoint: `nvidia/Qwen3.8-Flash-Next-FP4-Local` at its pinned revision (`b9ce18a6`)
- Levels are 1/2/4/6. Device scratch grows about 50mb per live drafting stream (4.11 -> 4.16GB at 2-6 streams, saw this on the boot lines); no level refuses at 131k token windows. 8 streams not ran - stock arm cant serve that at bf16 KV (32.86GB cache against 31.41 free).
- Paths this change reaches: the decode time copy proposer inside `core/lanes`. RAN on CUDA/GB10, did not run Metal/HIP/XPU
- Exactness/same checkpoint and settings:
  *   6/6 golden identical - every w64 reply is equal to the stocks own reply on every cell
  *   tools/bench_concurrent.py --alone --serial: 0 fails and 0 unmeasured requests at every level from both arms. The reply-level equality is simply the golden comparison and the workload hashes below.
  *   Every copy/rewrite/edit reply hash is equal between the two arms (1 distinct sha per (streams, kind); one harness-side probe crash on a single cell but its w64 value equates to up124's own at 2/4 streams).
- Main vs this branch, same box and check, the lever's own workloads (boot split medians of all runs, 2 boots an arm at 1/2 streams, up124 / w64 tok/s):

|
|       workload |    up124/w64 change |
| ------------- | ---------------------- |
|    1 word rewrite (1stream) |   228.8/256.7 +12.2%
| 2 concurrent edits, 1st / 2nd  | 141.1/137.7, 141.3/138.6 -2.4%/-1.9%(inside the boot spread, decode path is exactly the same between arms)
| edit next to a prose reply, edit / prose  |    147.7/147.8 and 47.4/47.4   0.0%
| verbatim copy (1stream)      |   374.3/473.7 +26.6%

verbatim copy does not move, which is exactly as expected - upstream already ramps a solo copy to `max_copy` 31. So the jump only makes the climb shorter and the 1800 token copy amortises it away.
Win is on the edit workloads that the source survives the mismatch
- decode speed before and after, maintainer's tools final head - 1 request at a time, greedy:
   `tools/bench_openai.py` 256 tokens, 2 passes an arm - code 73.8 / 73.4 stock against 72.9 / 72.9 port, gpu-chat 47.2 / 47.2 against 46.8 / 46.8
   `tools/bench_concurrent.py --alone --serial` (code, aggregate tok/s): s1 73.4/72.8, s2 72.8/72.1, s4 72.2/71.8, s6 72.1/71.7 - Every cell within 0.9%
   Boot split cell medians agree: 1 stream per stream prose 51.9/51.9, code 72.8 / 72.3 (2 boots an arm) - every 4/6 stream boot median within 1.5% of stock
-  Prompt speed before and after: n/a. Change is in the decode-time copy proposer and does not reach prompt processing.
- Licence of any new weights or drafter: n/a, no new weights.
## What is (deliberately) NOT included - and what the receipt proves

The 64x copy window is deliberately not here.
exact_width is the widest window that reproduces 1 token
steps bit for bit (upstream set this at 32 - commit `5bb64597d` which itself is already ramps lone copy from 15-31 drafts and keeps row counts pass the kernels 64->row switch unchanged). Raising `mtp.max_rows` to 64 is a kernel "row invariant" claim + a device scratch change.
This PR gets that receipt - as the boottime selftest measured boundary on the REAL weights (widths 1->48 are byte equal to their 1token steps at every row, width 49 is the first it differs) so the engine just serves 48x windows and falls back to upstreams 32 any time it sees a row differs with `TF_FLASHNEXT_WINDOW_CHECK=0` as the skip.
64x window itself is unclaimed on this checkpoint.

## Checklist

*   - title/desc match head commit (w/receipt, w/stack etc).
*   - new tests fail before the change, pass after it and skip clean without their dependency.  (4 faithful mutants, each killed by its own named test: prompt only arming gate, miss arming and shared round ramp/width)
*   - comments/docstrings are one liner. no measurements/histories in the source
*   - no personal data, machine names, internal hosts or local paths in the diff or its commits no AI attributions.
*   - no tokens still go through the lane rounds (no serial path, nothing that needs drafts off).
*   - drafted output == "draft": false, resumed prompt == fresh one and concurrent == solo
*   - I am not trading precision for speed here. The change is selecting which tokens are proposed as drafts; it changes no sum at all.
*   -     - Decode and/or Prompt processing is as fast or faster than main at 1x stream and widest admitted with copy policy on, edit workloads are faster and plain decode is dead in the water noise.