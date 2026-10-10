# Upstream PR (not posted): patches/0016: pooled sequences keep their CUDA graphs across requests

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w3-opus (`~/work/lanes/w3-opus/`, image `w3-opus-v5`, holds 1-4 and the POOL_MUTANT boots), merged image `zmerge2` (`merge/mverify3.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0016: pooled sequences keep their CUDA graphs across requests (short replies 9% faster, replies byte-identical)

**Body:**

## Description and Motivation

Every request gets a new sequence and frees it at the end, and a solo window's CUDA graph bakes in its
sequence's buffers: a one-client server re-captures its decode graphs request after request (about 200 solo captures
in a bench run, ~12 a request at ~3.5 ms each). A short request's sequence limit (prompt + `max_tokens` + window)
also caps its capacity, so the graph's context bucket and key differ per request. With two to four streams about two
thirds of the shared verify rounds ran eagerly anyway, and each captured verify graph was replayed ~2.6 times.

`patches/0016-flash-next-sequence-pool.patch` (one GPU):

- `TF_FLASHNEXT_SEQ_POOL=N`: up to N finished sequences are kept for the next request (`Engine.takeSeq` /
  `retire`). A pooled sequence reserves the engine's whole window, so every request sees the same capacities and the
  graph keys repeat. Back in the pool it is reset to exactly what a new sequence is: physical memory past the first
  growth step unmapped (the addresses stay reserved, so its graphs stay valid; `vmm.Region.shrinkToFirst`), every
  cache byte and the fixed state zeroed, then `Forward.reset` (~3.1 ms a request). If a new sequence or a cache growth
  would not fit, the idle pool and its graphs are freed first (`Forward.reclaim`), so pooling never causes a refusal.
- `TF_FLASHNEXT_WARM_POOL=N`: at load N pooled sequences capture the served one-stream shapes: the verify window at
  every width 1..16 and both parities, and the one-stream MTP steps (they go through the shared graph table even at
  one client).
- `TF_FLASHNEXT_MULTI_LRU=1` evicts the least recently run shared graph when the table (`TF_FLASHNEXT_MULTI_MAX`) is
  full, instead of dropping them all; `TF_FLASHNEXT_SOLO_MAX` caps the solo graphs the same way.
- `TF_FLASHNEXT_MULTI_VERIFY=1`: shared verify rounds of two or more streams run eagerly; shared MTP steps stay
  captured up to `TF_FLASHNEXT_MULTI_GRAPHS`.
- The boot log says `graphs: shared verify rounds of up to 1 streams captured, ...; sequence pool 4` and `graph
  warm-up: N graphs on 4 pooled sequences`.

Why the replies do not change: a graph replays the launches its eager run made, and a pooled sequence starts from the
same bytes as a new one (caches and state zeroed, positions reset). Running a verify round eagerly instead of from a
graph is the same launches.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Lane image (this patch on the stock engine), hold 4: three boots an arm after a discarded first boot, summed
elapsed seconds a section (lower is better):

| section | stock | 0016 | change |
| --- | ---: | ---: | ---: |
| 8 short (100-token) replies, 1 client | 3.58 / 3.57 / 3.54 | 3.23 / 3.22 / 3.25 | -9.4% |
| first request after boot | 0.18-0.19 | 0.16 | -14% |
| code 512 tokens, 1 client | 4.48 / 4.46 / 4.47 | 4.34 / 4.31 / 4.29 | -3.6% |
| prose 512 tokens, 1 client | 7.05 / 6.84 / 6.88 | 6.80 / 6.77 / 6.65 | -1.6% |
| short replies, 4 clients | 18.69 / 18.37 / 18.37 | 17.50 / 17.76 / 17.29 | -4.7% |

Every run of these sections beat every stock run; long replies at two and four clients gained 0.7-2.3% inside the
spread. Merged build (with `0012`, `0013`, `0017`; tok/s): code 1 / 2 / 4 clients 117.6 / 85.3 / 59.5 -> 121.4 / 86.7 /
59.4, prose 68.0 / 55.0 / 38.5 -> 69.2 / 55.6 / 38.9, 12 short replies 17.70 / 16.98 s -> 16.22 / 16.64 s.

The campaign's graph counters (`TF_FLASHNEXT_GRAPH_STATS`), its capture-on-sighting knob and its pool mutant switch
are not in this patch.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. Every bench reply was byte-identical across arms (141/141 in hold 4, 94/94 in each earlier hold).
- The byte checks see a state leak: a switch that carried the last request's DeltaNet, conv and PLE states over and
  skipped prefill's own reset gave golden 3/6 and 18 of 33 short replies different (the switch was for that check
  only and is not in this patch). Skipping only the pool's own reset, or only the zeroing, changed nothing: prefill
  resets a sequence too; the patch keeps both so a reused sequence matches a new one byte for byte.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: a pool of 4 held ~1.8 GB at the end of a bench (15.9 vs 17.7 GB free); free memory after boot on the
  merged build 18-19 GiB against 19-22 GiB. Idle pooled sequences are given back before a request or a growth would be
  refused. I did not re-check the startup estimate at the template's 5 x 262,144 int8 setting, hence the box below.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR], #[0015's PR] merged first (logically it needs none of them). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [ ] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
