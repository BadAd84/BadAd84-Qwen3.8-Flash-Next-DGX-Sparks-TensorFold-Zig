---
name: audit-huggingface-model-finetune-tree
description: "Audit a HuggingFace model's finetune/quant/merge/adapter tree via the HF API to find derivatives aligned to a goal (coding/uncensored/cyber/hardware) - scoring then card-verifying candidates. Use when asked 'are there good finetunes/quants of model X' or for a better base for training."
---

# Audit a HuggingFace model's finetune/quant tree

Use when the owner asks whether good finetunes/quants of a model exist, or wants a
"better base for our own training." Runs fully via the public HF API (no auth for
public repos) from `eval`/urllib. Zero-hallucination path: enumerate mechanically,
then VERIFY each candidate's card before reporting.

## API mechanics (all under `https://huggingface.co/api/`)
- **Resolve base repo:** `models?search=<name>&sort=downloads&direction=-1&full=true`.
  Names may be post-cutoff - never assume the repo id, search for it.
- **Derivative tree (the site's "Model tree"):** `models?filter=base_model:REL:ORG/REPO&limit=1000&full=true`
  for REL in `finetune`, `quantized`, `merge`, `adapter`. Paginate via the `Link`
  response header `rel="next"`. (Validated working on a known model first.)
- **Catch untagged derivatives:** ALSO `models?search=<base-name>` - many good
  derivatives never set `base_model` metadata and only match by name. Dedupe.
- **Verify a candidate:** `models/<id>?full=true` -> `cardData.base_model`,
  `cardData.license`, `safetensors.total` (param count!), `gated`, `lastModified`,
  `pipeline_tag`.
- **README:** `https://huggingface.co/<id>/raw/main/README.md` (strip leading
  `---...---` YAML frontmatter). A 401 means the repo is gated.

## Method
1. Resolve each base repo via search.
2. Enumerate all 4 relations + name-search; dedupe into one set per base.
3. Score each by keyword category in id+tags: CODE (`coder|code|swe`), UNCAP
   (`abliterat|uncensor|heretic|decensor|derefus`), SEC/RE
   (`cyber|pentest|exploit|malware|redteam|reverse|ghidra`), AGENT
   (`agent|tool-call|function`), REASON (`reason|think|distill`); note runnable
   formats (`exl3|gguf|awq|nvfp4|gb10|mtp|fp8`). Rank by downloads/likes.
4. VERIFY the top candidates (detail + README) before reporting ANYTHING.

## Traps (each cost a real correction)
- **Names lie - verify base/license/params/README first.** Report author quality
  claims AS claims (you did not benchmark them); recommend the owner's agentic
  oracle-bench to gate finalists before spending training compute.
- **`safetensors.total` unmasks fakes:** a "27B agentic/coder" repo reporting
  ~1.4-1.9B params is a DRAFTER/LoRA/adapter, not the model. The huge-download
  `*-DFlash2` repos are ~1.9B MTP SPECULATORS (decode speed), NOT coding finetunes.
- **`base_model` can be mislabeled** (a "Qwen3.8 coder" whose real base is
  Qwen3.6-35B) - trust the metadata field, flag mismatches, don't infer from name.
- **Keyword `binary` false-positives SEC/RE** (a `-verifier-binary` is a verifier).
  Re-check the card.
- **GGUF/MLX/merge repos are inference-only** and often off-stack (CPU / Apple
  Silicon) - poor training bases. Full safetensors + apache-2.0 = good training
  base. For training, finetune FIRST and abliterate LAST (stacking SFT on an
  already-abliterated base can reintroduce refusals).

## Output
Per-model coverage line (N derivs, M real finetunes) + a ranked shortlist by the
owner's goal, each row with dl/likes/license/base/params evidence and format.
Separate TRAINING BASES (full weights, clean license) from READY-TO-RUN (quant
on the owner's stack) from SPEED ARTIFACTS (drafters / GB10 quants).
