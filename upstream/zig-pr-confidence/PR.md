# Upstream PR #34: config TF_FLASHNEXT_CONFIDENCE=-0.15 (posted 2026-10-09)

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: `scripts/qwen38/zig/` A/B rows on spark6 (2026-10-08 arms `stock` / `c015`, and the threshold sweeps),
`docs/ZIG-SPEED-CAMPAIGN-2026-10.md`.

---

**Title:** config: TF_FLASHNEXT_CONFIDENCE=-0.15 on one Spark (prose decode +7 to +10%, replies unchanged)

**Body:**

## Description and Motivation

`scripts/config.sh` now sets `TF_FLASHNEXT_CONFIDENCE=-0.15`. Before, it was unset, so the engine used its own
`-0.4`: the running-product draft stop, applied while at most `TF_FLASHNEXT_PRODUCT_STREAMS` (2) streams are live. The
engine's comment says `-0.4` was tuned at TP=2. On one Spark longer chains pay off: with `-0.15` a chain stops once its
drafts' joint chance falls under 0.15 instead of 0.4.

Only where a chain stops changes. Every draft is still verified, so every reply stays byte-identical. Above two live
streams nothing changes (the per-draft rule at 0.5 applies there).

Measured on one DGX Spark through the recipe's own server, stock image `tensorfold-qwen38:zig-db28187`, defaults
otherwise. Per-request decode tok/s, greedy, thinking off, 512-token replies, prose and code prompts, medians of two
boots an arm:

| | stock (`-0.4`) | `-0.15` | change |
| --- | ---: | ---: | ---: |
| code, 1 / 2 / 4 clients | 103.8 / 75.5 / 53.0 | 106.5 / 76.1 / 52.8 | +2.6 / +0.8 / -0.4% |
| prose, 1 / 2 / 4 clients | 61.2 / 50.1 / 36.5 | 67.4 / 53.5 / 37.3 | +10.1 / +6.8 / +2.2% |

At four clients the per-draft rule applies in both arms, so those cells compare the same setting (code at four
clients moves a few % between boots on this box either way).

We swept the threshold first (-0.1, -0.15, -0.2, -0.25, -0.3 against -0.4, two or three boots an arm). Lower
thresholds help prose most; -0.1 and -0.2 traded about 2% between prose and code; -0.15 was the best balance.
`PRODUCT_STREAMS=4` (the product rule at four streams too) made code at four clients slower (54.8 -> 49.0 tok/s), so
it stays 2.

README "Configuration" gets a row; the CHANGELOG gets an Unreleased entry.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical between the arms in every boot.
- `tools/exact.py` against a server with this setting: PASS (6 drafted replies equal the `"draft": false` ones, 522 drafts accepted; 6 concurrent replies equal the one-at-a-time ones), on the server built with all three of my PRs and this setting.
- The A/B: each arm booted fresh by `./start.sh restart` with the setting in the environment, one pass of the decode
  matrix a boot, arms alternating, the order reversed the second cycle.
- `bash -n start.sh stop.sh scripts/*.sh`; shellcheck adds no finding.
- Memory: unchanged (a draft stop setting only).

Other PRs from me in this batch: #35 (`patches/0010`, argmax/logsumexp launch width) and #36
(`patches/0011`, the MTP layer on block FP8). All three add CHANGELOG/README/CREDITS lines in the same places;
whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
