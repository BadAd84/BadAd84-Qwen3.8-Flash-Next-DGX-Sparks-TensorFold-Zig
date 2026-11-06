# Affine-3 routed decode tile mis-pick at 4 rows (found 2026-11-06)

Measured on a free spark6 under flock, against the ai-engine up1105s image (shared engine tree),
running `tf-cuda-test experts3 200`. The affine-3 routed experts kernel (`Affine3Experts`,
`zig/src/cuda/experts3.zig`, used by the qwen3_5 family) picks between two decode tiles:
`split`/`split_fn` ("a block a CTA", more parallel) and `pair`/`pair_fn` ("a block a warp", more
resident work). The choice is `split = pair and units < split_below` (experts3.zig:84), with
`split_below = 4 * resident[0] * 7 / 8` (experts3.zig:60).

Measured up-projection decode times (512 by 2048, 9 picks a row):

| rows | CTA (split) | warp (pair) | chosen | faster |
|---|---|---|---|---|
| 1 | 28.7 us | 38.2 us | CTA | CTA |
| 2 | 51.2 us | 53.9 us | CTA | CTA |
| 3 | 65.2 us | 64.3 us | warp | tie (warp +1.4%) |
| 4 | 90.8 us | 109.2 us | **warp** | **CTA by 17%** |

At 4 rows the heuristic switches to the warp (pair) kernel, but the CTA (split) kernel is 17%
faster there (90.8 vs 109.2 us). `split_below` cuts over one row too early. CTA is faster at
1, 2 and 4 rows and tied at 3, so raising `split_below` to keep the split kernel through 4 rows
is a bit-exact win (the test already proves both tiles byte-equal to affine-4 and FP64 at every
row count). The exact threshold should be re-measured across the real routed `units` range, and
the change A/B'd on the qwen serve at 1/2/4/6/8 streams under this repo's no-regression rule.

Not a GLM lever: GLM-5.3-Flash routed experts are NVFP4 (`Affine4Experts`), a single-grid launch
with no warp/CTA choice. This is affine-3 (qwen3_5) only.
