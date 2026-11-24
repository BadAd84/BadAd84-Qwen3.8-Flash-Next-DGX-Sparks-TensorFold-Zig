# Provenance: files in this repo that came from another project

Answer to one question, for this repo only: which files here contain another project's code, and what
must this repo's agent do about each under the no-copying rule (`AGENTS.md`, "No copying"; fleet
`RULES.md` section 8). The repository's own agent owns this list; it is not tracked from another repo.

## How each line was found

## Method and the search commands

Tracked files only (`git ls-files`). Two regions scanned:

1. The header region (first 30 lines) of every tracked source, kernel, script and doc file.
2. The added (`+`) side of every tracked `.patch` and `.diff`, including each numbered package's
   new-file headers, because a file that entered through a patch is the case at hand.

Search commands actually run (one per repo, `$R` = the repo dir):

```
git -C "$R" grep -nIE '(^|[^A-Za-z])(From[: ]|Copyright|Apache|MIT License|BSD-|derived from|adapted from|based on|port(ed)? of|port(ed)? from|MiaAI-Lab|Marlin|llama\.cpp|vLLM|FlashInfer|CUTLASS|Triton|cuBLAS|NVIDIA Corporation|taken from|copied from)' -- .
```

then narrowed to two high-signal patterns, applied to the header region of tree files and the `+`
lines of patch/diff files:

```
attribution : (From MiaAI-Lab|Mia's AI Lab|jayleaton|Jay Leaton|Arminova|manuel1618|BertholomusAI|drowzeys|wojo|eleqtrizit|mxfp0|Jason Cook|Turboderp|ExLlama|ExLlamaV3|lukaszraczylo|CUTLASS|FlashInfer|Marlin|llama\.cpp|vLLM)
licence+copy: (Copyright (\(c\) )?20[0-9][0-9] [A-Z]|SPDX-License-Identifier|Apache-?2\.0|Apache License 2\.0)
```

High-signal transcript: `work/provenance/highsignal.json` (123 hits); full marker transcript:
`work/provenance/raw_hits.txt` (3669 raw lines, most noise). Extractor: `work/provenance/extract.py`.

## The false-positive rule, with a worked example

Marker text alone is not a hit. A line is a HIT only when it names a party OUTSIDE these five repos
as the origin of the code the file contains. The test is provenance, not vocabulary.

Example line that is NOT a hit:

```
scripts/glm53/v110/hunt/HuntMatmulExperts/pt/tensorfold.orig/families/glm5_next/cuda/exl3.cu:3
// Format (see exl3.py, after ExLlamaV3, MIT, Copyright (c) 2025 Turboderp): a 16x16 tile is ...
```

Not a hit because the sentence cites ExLlamaV3 as the origin of the EXL3 **tile format** (an interface
the kernel reads and writes), and the file is upstream TensorFold's own `exl3.cu` (the `.orig` path is
a verbatim copy of the pristine tree's file). Citing a format we implement is the OURS arm, not the
copied-source arm. The same rule clears our knobs whose citation is a GitHub issue, and our
`derive*.py`/`score*.py` whose "derived from" names our own rows.

The other false-positive family: "copied from" naming OUR OWN file. Example:

```
patches/engine/0020-onepass-pipe.patch:94
+// Copied from glm_onepass.cu for the measurement pipeline (glm_onepass.pipe.cuh), separate namespace; keep in sync.
```

Not a hit: `glm_onepass.cu` is ours, in the same series.

## Notice state across the five repos (the baseline for DECLARED / UNDECLARED)

- No repo tracks a `THIRD_PARTY_NOTICES`, `NOTICES`, `LICENSE`, `LICENSES/` or `COPYING` file
  (checked: `git ls-files | grep -ciE 'THIRD_PARTY|NOTICES|^LICENSE|^LICENCES/|COPYING'` = 0 in all five).
- The ONLY third-party notice anywhere is inside Qwen patch `0029`, which EDITS upstream TensorFold's
  own `THIRD_PARTY_NOTICES.md` (`diff --git a/THIRD_PARTY_NOTICES.md b/THIRD_PARTY_NOTICES.md`, an edit
  of a 459-line upstream file, not a new file). So the notice exists in the built tree but not in our repo.

Therefore, for classification below:
- **DECLARED** - a notice or a patch RECORD/section names the file and its licence/copyright.
- **UNDECLARED** - the file's own header names another project, but no notice or RECORD entry carries it.
- **OURS** - no external-origin marker in the file; the negative search that found nothing is shown.


## This repo's findings

### 1.1 DECLARED - the INT4-AutoRound kernel port (the one real copied-source case)

| | |
|---|---|
| Path | `zig/kernels/cuda/fn_int4.cu` (added) plus `zig/src/families/flashnext/cuda_int4.zig`, `zig/src/families/flashnext/cuda_int4_load.zig`, `zig/src/cuda/int4.zig` (host packers/launchers, ours) |
| Header line | `patches/main-1ece6e6db-r5-dev/0021-int4-autoround.patch:59`: `+// From MiaAI-Lab's dual-Spark recipe at 04f2b53826, patches/0002-kernels.patch, Apache-2.0, Copyright 2026 MiaAI-Lab.` |
| Licence / copyright | Apache-2.0; `Copyright 2026 MiaAI-Lab`; recipe commit `04f2b53826dca9a52893f2bce9d49bb3d1828e88` |
| How it entered | numbered patch `0021-int4-autoround.patch` (new file mode 100644). The MiaAI-Lab header line is carried by exactly THREE patch files: `patches/main-1ece6e6db-r5-dev/0021`, `.../main-1ece6e6db-r5-int4/0021`, `.../main-1ece6e6db-r5-int4-kvtier/0021` (verified: `git grep -lE '^\+// From MiaAI-Lab'` over every patch that adds the file). The other packages that add `fn_int4.cu` - `main-1ece6e6db-r2-int4/0021`, `1.2.7-int4/0016`, `main-964174ea05-int4/0016`, and the `scripts/qwen38/zig/merge/zmerge{3,4,5}.patch` folds - carry a DIFFERENT header: `//! Source: the production branch's zig/src/families/flashnext/cuda_int4.zig and fn_int4.cu at 5c3e3e29 (our own engine fork)`. So the MiaAI-Lab attribution was added only in the r5 re-cut; on those older packages the file's own text names our own engine fork as the origin |
| Our changes marked? | Yes, in the file itself: the header states "TensorFold changed three things ... each marked TF:" and the notice repeats it |
| Notice | `patches/main-1ece6e6db-r5-dev/0029-int4-contract-suite.patch:1659-1670` adds a `## MiaAI-Lab Flash Next int4 kernel` section to upstream's `THIRD_PARTY_NOTICES.md` naming the file, the recipe commit, Apache-2.0, the recipe's own NOTICE text, `LICENSES/Apache-2.0.txt`, and the three changes |
| Status | **DECLARED** (in the patched tree); not present in this repo's own tracked tree |

Owner decision line: keep with notice (the header, the copyright line and the `THIRD_PARTY_NOTICES`
section already land together, which is exactly the exception the rule requires; the only gap is that
the notice file is not tracked here), OR rewrite `fn_int4.cu` from TensorFold's own GPTQ spec and drop
the notice. Do not decide.

### 1.2 Everything else in this repo - OURS

The tree files (`scripts/`, `docs/`, `patches/*/RECORD.md`, `upstream/*`) contain no external-origin
marker. Negative search, applied to the tree files of this repo, returned only two lines, both a knob
table cell citing a GitHub issue (not code origin):

```
docs/knob-receipt-2026-11-20/CLASSIFY.md:27   ... | cuda; native CUDA admission ... | #133 MiaAI-Lab 2026-09-30
docs/receipts/KnobTest/CLASSIFY.md:27          (same row)
```

The `upstream/qwen-pr-copy-first/` package declares a port of `TensorFold #319 by Arminova`, but that
is the PR's own description of a change re-seated onto upstream from upstream's own history, and the
"port" is from one TensorFold version to another (0.6.4 to v0.6.1) - same project, not another one.
No other file in this repo names an outside project as its origin.

---

## Files here that came from another engine or library

- **Qwen** `fn_int4.cu` and its host companions: MiaAI-Lab's dual-Spark recipe (an engine recipe). [DECLARED]
- **GLM Zig** engine patches 0012 (`select_split`) and 0031 (jayleaton 0580): another engine's kernel
- **GLM Python** `kept_reasoning.py` (jayleaton 0620 on 6 files; also MiaAI-Lab recipe 0036's file kept
- **DeepSeek** `ots-patches/recipe/` (MiaAI-Lab's 48 recipe patches, i.e. a whole engine's patch set)

## The decision, per file (the owner decides; this page lists the options)

- **Keep with notice**: the licence, the upstream copyright line and a `THIRD_PARTY_NOTICES` entry
  land together, which is the exception the rule allows.
- **Rewrite from TensorFold's own specification**, with the reference source closed while we write it.
- **Remove**, with the lever it serves retired in the same change.
