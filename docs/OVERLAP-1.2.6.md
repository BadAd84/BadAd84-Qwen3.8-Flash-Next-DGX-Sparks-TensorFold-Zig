# Overlap: what upstream v1.2.6 already carries of our levers

Upstream moved twice after the base the port campaign was built on. v1.2.5 is `8be9c408c` (2026-11-08) and
v1.2.6 is `6e9af9302` (2026-11-10, the current release). Relative to v1.2.4 (`267c5af6a`, the campaign's
base) that is 654 commits and 1,644 files (+402,645 / -5,539). The modern branch is now `1.2.6` in
`ots/tensorfold-levers124` (tip `6e9af9302`); `main` there is the current production stack
(zmerge8-kfix). The 1.2.4-based port branches are archived as `archive/*` tags.

Method: every setting our serve sets, and every symbol our levers introduce, grepped in the `v1.2.4` and
`v1.2.6` trees (files containing it) and against the range's commit log (`git log -S`), plus the family's
own constants. Scripts and raw output: `work/overlap126.sh`, `work/overlap126b.sh`,
`work/overlap126.txt`, `work/overlap126b.txt`.

## Verdict table

| our lever (1.2.4 port branch) | in v1.2.6? | evidence | action |
|---|---|---|---|
| warm turns (port-warm-turns) | **yes, upstream** | `zig/src/server/warm.zig`, `core/lane_host_warm.zig`, `engine_api.zig` `warm_turns`; present in v1.2.4 too (20 files, 21 in v1.2.6) | take upstream's; drop our port and only enable it |
| 48-row copy window + boot self-check (port-64rows-v2/v3) | no | cap still `mtp.max_rows = 32` (`families/flashnext/cuda_mtp.zig:84`); `WINDOW_CHECK` 0 files in both | port as our first lever; the measured boundary was 48 rows on NVFP4 |
| copy re-sync + shared ramp (port-copy-windows, -ab4b2f05) | no | `resync`/`COPY_RESYNC` 0 files in both | port unchanged |
| keep-late rows folded into the next verify (0012) | partly | upstream has the mechanism: `TF_FLASHNEXT_KEEP_LATE` in `families/flashnext/cuda_batch_late.zig` (6 files in both versions); the folding into the next verify pass is not there | keep upstream's mechanism, port only the folding |
| n-gram gather of all lanes in one pool call (0010) | no | `families/flashnext/cuda_batch.zig:510` gathers per row on a spawned host thread; no multi-lane call | port unchanged |
| n-gram pread read-ahead + chunk-tail rule (0013) | partly | upstream has `TF_FLASHNEXT_WARM_AHEAD` (`cuda_ple.zig:381`) and pread in `checkpoint_cache.zig`; no page-cache read-ahead or chunk-tail rule | port the read-ahead half, re-derive against WARM_AHEAD |
| fp8 KV cache for Flash Next (0003) | no | family `kv_cache_quant_algo` is validated only (`cuda_config.zig:124`); no kv8 path in `families/flashnext` | port unchanged |
| sampled GPU top-k, sampled streams in the batched head (0007/0008) | no | no such symbols in either tree | port unchanged |
| fp8 prompt tiles + int4 gate/up (0006), MX128 two-stage tile (0015) | partly | upstream added BF16 qmmf prompt tiles (`ec76abd45`, `d91a68496`, `fbf8d960d`); `mx128`/`MX128` 0 files | port; re-derive the tile crossover against upstream's BF16 tile choice |
| persisted prompt-state keying / cache salt (0027) | **superseded** | v1.2.6 keys states by what the loaded run computed with (`f7456238d`, `5fdcadcaa`, `42ff6c510`, `296848a7a`) and rewrites the cache for 8-16 agents (#2699) | take upstream's design; our salt work is not needed |
| shared-expert early fork, slot store (0028) | no | `sharedEarly` 0 files in both | port unchanged |
| batched draws (0017) | no | `batchDraws` 0 files | port unchanged |
| draft head 4-bit default + head row tiles (0021) | no | `draftHead4`/`head_row_tiles` 0 files | port unchanged |
| 12-bit read-out weights (0022) | no | `q12`, `readout12` 0 files | port unchanged |
| round cost model / shared cost levels (0026) | no | `sharedCostLevels`, `confidenceFor` 0 files | port unchanged |
| product stop rule (`PRODUCT_STREAMS`) | no | `PRODUCT_STREAMS` 0 files; upstream has only the `draft_confidence` floor | port unchanged |
| kindling upload staging (0050) | **yes, upstream** | fixed by copy custody `096200f02` (`copy_source.zig` `syncChunk`), in v1.1.4 and later | nothing to do |
| lane-batched DeltaNet (0016 part) | partly | HIP prompt DeltaNet only (`e1da6cb67`, #2582); no CUDA lane batching | port the CUDA half |

## What v1.2.6 changes about the target numbers

1. The prompt cache is rebuilt for concurrent agents (#2699): on a GB10 a follow-up's median first token
   at 16 agents drops from 105 s to 25.8 s. That is the metric our target table must beat, and it is
   measured in the target sweep (TTFT cold plus the warm next turn, idle and under load).
2. Flash Next's window caps are unchanged from v1.2.4 (`max_rows` 32, `round_rows` 64, `MAXR` 16), so the
   48-row result still applies at the same place.
3. v1.2.6 still serves Flash Next with bf16 KV unless a change lands, so 6 and 8 streams at 262,144
   tokens do not fit on stock (32.9 GiB of bf16 cache against 31.4 free on the INT4 serve's numbers).
   The stock 1.2.6 arm of any A/B therefore runs 131,072-token windows or 5 streams, and says so.

## Branch layout in ots/tensorfold-levers124 (2026-11-10)

| branch | content |
|---|---|
| `main` | the zmerge8-kfix production stack: the recipe 1.0.0 patches, 0010-0028, tfm-fixes, tfm-warm-t and c68-shared-cost-levels, 23 commits over TensorFold `db281878` |
| `1.2.6` | upstream `6e9af9302`, untouched |

The 23 former port and series branches are tags `archive/<name>` on the remote (their content is also in
`scripts/qwen38/zig/levers124/*.patch`). `rows126` (local until it is measured) is the 48-row lever
rebased onto `1.2.6`: six commits, with three conflicts resolved against 1.2.6's own API (the batch path's
`self.k.forms.gdn_fused`, and the changelog's Unreleased section placed above the 1.2.6 section). Its
receipt files still carry the 1.2.4 measurements (`up124` against `w64`) and are replaced when the lever
is re-measured on 1.2.6.
