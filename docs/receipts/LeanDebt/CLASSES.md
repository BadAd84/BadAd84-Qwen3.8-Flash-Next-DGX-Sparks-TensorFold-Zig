# Lean findings the r5-dev composition adds (measured 2026-11-25)

The pair, run as CI does it: base and head each their own tree root and their own copy of
`tools/zig/lean_check.py`, base first then head through `lean_new.py`.

```
base 1ece6e6d applied 40 of 41 (the 41st is patch 0041): 6993 files, 168 problems
head: 7026 files, 192 problems
lean: 192 problems, 168 on the base, 24 new
```

## The 24, by rule

| rule | count | files | class |
|---|---:|---|---|
| over 600 lines | 13 | qmmf.cu, lane_host.zig, lanes/depth.zig, lanes/stream.zig, lanes/windows.zig, cuda/qmmf.zig, cuda_batch.zig, cuda_glue.zig, cuda_lanes.zig, cuda_ple.zig, cuda_prompt.zig, cuda_prompt_wt.zig, contract_tests.zig | not fixed: the rule's fix is splitting a module, a code-structure change, and a comment trim cannot pay for it |
| direct getenv | 6 | cuda_hc_q12.zig (HC_Q12), cuda_mtp_check.zig (CHECK_LOG), cuda_mtp_mxfp8.zig (MTP_WEIGHTS), cuda_startup_phase.zig (a non-literal name, TENSORFOLD_COPY_MISS, TENSORFOLD_COPY_RAMP) | not fixed: reading through platform/environment.zig adds table rows and changes refusal behaviour, which is a code change the port did not need |
| multi-line comment | 5 | cuda_knobs.zig (3 blocks, this patch's own), qmmf.cu, cuda/qmmf.zig | fixed for the knobs blocks in 0041; the two port blocks are recorded below |

## What the earlier pass got wrong

The previous clean-up cleared comment findings and reported the tree clean without proving the
non-comment set was absent, and two lanes then died in loops before re-measuring. This pass ran the
pair on a tree with the whole series applied, which exposed a worse problem than the findings: the
committed patch 0041 did not apply at all (git apply rejected six hunks; only patch --fuzz applied
it), so every measurement taken against "the applied head" between the patch's commit and this repair was
taken against a tree missing that patch: committed `1c8e549d0` 2026-11-24 22:57:47 +0000 and amended
`b2cfb2dc2` 2026-11-24 23:07:40 +0000, repaired and re-proven at `b60592871` 2026-11-25 13:02:27 +0000, so
under fifteen hours. 0041 is now rebuilt as a real diff against the forty-patch tree and the series
applies 41 of 41 from an absolute root.
