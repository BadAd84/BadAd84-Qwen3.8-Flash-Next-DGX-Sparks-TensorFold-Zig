Title: flashnext: load the MTP draft head rows 4-bit by default

What this changes:
The MTP draft head's row weights load in bf16. The loader already has the affine4 path, and the GLM family already packs its draft head 4-bit. This flips Flash Next's default to `.affine4`: two files, one default and one discriminating test. The recipe never sets `TF_FLASHNEXT_DRAFT_HEAD`, so the code default is what the production recipe runs; any serve that wants bf16 rows sets it back.

The fp8 attention-reader half of the recipe this change comes from is not here (it builds on the KV8 cache path, which is a separate change, this one carries only the checkpoint agnostic half).

  *   Issue: n/a, it is just which precision the draft head's rows load in; the draft is still accepted only if it equals the plain token - so no arithmetic moves on the served path.
  *   Stacked on: main
  *   Overlap: `atc overlap` swept all 202 open upstream PRs (6 touch the file, all adding an EXL3 draft hook inside `draft()`, none touch `mode()` or the default).
    

Checks on this head:
  *   Head commit: `d6197769` (the port, the discriminating test and the CHANGELOG bullet), on upstream `267c5af6a`; both A/B arms built from that tip.
  *   `tools/pr_check.py --base origin/main` - 0 errors, 0 warnings, 3 changed files, lean 116vs116, 0 new
  *   Tests: Base and head build the same steps (with exact same failing test list - the 3 stock env fails), equal per test pass count and the added test is discriminating - a mutant flipping the constant to `.bf16` turns exactly that test red (verified in a scratch copy).    
  *   Exactness: Golden 6/6 identical on all 12 ABBA cells (reader124 gated on stock's own reply per cell); boots 35-40 s
  *   Model memory:
    *   76.16 -> 75.89 GiB (for the 4bit head rows)
    *   Decode, Aggregate tok/s, medians, stock / reader124: Code 72.9 / 78.3 @ 1st stream, 102.6 / 106.9 @ 2, 127.5 / 135.8 @ 4, 165.5 / 181.4 @ 6
    *   Prose 52.4 / 57.6, 69.6 / 71.6, 95.4 / 99.8, 115.0 / 126.2; the rewrite probe 229.1 / 239.5; the copy probe 375.2 / 379.5
  *   Not run:
    *   Metal, HIP and XPU host tests (the box is CUDA only); no GPU kernel contract (no kernel changes - it is a loader default).
  

Checklist:
  *   [x] The title and description match the head commit and the measurement.
  *   [x] The added test fails if the default is flipped and passes on the head; a mutant proved it.
  *   [x] Comments and docstrings are one line. No measurements or history in the source.
  *   [x] No personal data, machine names, internal hosts or local paths in the diff or its commits.
  *   [x] No precision traded for speed on the served path - the draft head's rows load smaller and the accepted-token rule is untouched.