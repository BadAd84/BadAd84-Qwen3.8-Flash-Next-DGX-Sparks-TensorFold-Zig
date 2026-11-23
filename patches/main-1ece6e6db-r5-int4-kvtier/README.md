# TensorFold main `1ece6e6db` + r5 + INT4-AutoRound + the persistent KV tier + the pool's cache refusal

The combined directory: upstream main at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, then `patches/main-1ece6e6db-r5`
0001 to 0020, then five patches in filename order. It exists because a device window builds one image from one
directory, and this is the tree it gated: the INT4 port that serves production's checkpoint, the KV tier that keeps
conversation states, and the plan-time refusal that stops the tier from being silently inert.

    ./apply.sh --check TREE     # the series and the five apply in order, nothing written
    ./apply.sh TREE             # apply them

An image of this series serves `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` only: the routing width is a
build-time constant (`slots = 6`, `shared_w = 1280` in `cuda_prompt_wt.zig`) and the config check refuses the FP4
checkpoint by name (`num_experts_per_tok`).

## The five patches, each byte-identical to the package it came from

| patch | source | sha256 |
|---|---|---|
| `0021-int4-autoround.patch` | `patches/main-1ece6e6db-r5-int4/0021` | `3cffe99044c6ffd14820a8bc88085cc6e18990bddb5a5ab90d57223de4dda1a1` |
| `0022-int4-serving-pins.patch` | `patches/main-1ece6e6db-r5-int4/0022` | `18ab81216fa104ea1853f27b60ccf9e88355ed7dde2aa976ff7d08b06bf11c26` |
| `0023-kv-tier-fp8.patch` | `patches/main-1ece6e6db-r5-kvtier/0021` | `47d90e3b5f71cd9a0404bb6f1ce836e09f709ebea44851308e8440e65d479dc7` |
| `0024-kv-tier-dedup.patch` | `patches/main-1ece6e6db-r5-kvtier/0022` | `cd5a336200f7c218fa53e52fdc11d51f2ee2b34a4010fcb4dda297e15ebda864` |
| `0025-kv-tier-pool.patch` | `patches/main-1ece6e6db-r5-kvtier-pool/0023` | `e6a4872ed53041d3e5e4b850a3733dadba764b15c54941420bd4b480a9032589` |

There is no code of this directory's own: it is the four packages composed, with the tier's `0021` and `0022` and the
pool's `0023` renumbered to sort after the INT4 pair. Each patch's own documentation is the package it came from,
`README.md` and `CHANGES.md` beside its source: the INT4 port's shape and its upstream gap
(`patches/main-1ece6e6db-r5-int4`), the fp8 image and the append dedup (`patches/main-1ece6e6db-r5-kvtier`), and the
refusal's predicate and text (`patches/main-1ece6e6db-r5-kvtier-pool`).

## Why these four together, and in this order

- The INT4 pair first, because the device's checkpoint is INT4 and the tier's measurements have to be on the arm that
  will serve them.
- The tier's fp8 image next, because the served shape is fp8 KV; `--kv-cache fp8` with `--learn-conversations` was
  refused at the image (`copyable` accepted bf16 only) until `0023`.
- The append dedup after it, because the dedup is measured on the fp8 image and depends on it.
- The refusal last, because it is a predicate over the finished plan, which only exists once the pages, the cache and
  the store's slots are all decided.

Nothing between them conflicts: the INT4 pair touches the port and the serving fixture, the tier touches
`cuda_disk.zig`, `cuda_kept.zig` and `prompt_cache.zig`, and the refusal touches `cuda_streams.zig` and one call site in
`cuda.zig`. The gate run applied all five in order on a pristine base and recorded the file counts.

## The served shape this directory was gated at

Production's shape: `--parallel 8`, `--context 262144`, fp8 KV, the KV page pool on (`TF_FLASHNEXT_KV_PAGES=4096`),
the KV tier on its own budget rather than the plan's leftovers:

    CHECKPOINT=int4 VISION=0 KV_DTYPE=fp8 PARALLEL=8 CONTEXT=262144
    TF_FLASHNEXT_KV_PAGES=4096
    --prompt-cache-gib 6 --prompt-cache-disk <root> --learn-conversations
    --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20

with the INT4 drafter arm the INT4 package measured (`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`,
`TF_FLASHNEXT_DRAFTS_GREEDY=15`, `TF_FLASHNEXT_SHARED_DRAFTS=0`, `TF_FLASHNEXT_GREEDY_WIDE=8`). `--prompt-cache-gib 6`
is an ask rather than a grant: the plan's own startup line at this shape reports a 3.1 GiB prompt cache, which holds a
100,000-token state (about 1.9 GiB) and not a full 262,144-token one (about 4.7 GiB), because the streams' pages take
the rest of the room.

The block belongs in `scripts/qwen38/zig/target/env/dev.env` only once it is measured on this engine; `prod.env` stays
production's.

## What this directory does not do

It adds no behaviour and no setting of its own. The INT4 port is still a dev route, not the maintainer's six upstream
steps on issue #3368 (`patches/main-1ece6e6db-r5-int4/README.md` has the table, carried from the r2-int4 package and
true at 2026-11-21). The tier still has no staging ring, no store pin and no block-name lineage (the design's items 8
to 10); the refusal is not a sizing change, and a shape whose plan leaves the cache no bytes is refused rather than
served with a dead tier.
