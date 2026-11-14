# TensorFold 1.2.7 + INT4-AutoRound (experimental, not the accepted series)

Applied on top of `patches/1.2.7` (0001 to 0015) to a pristine v1.2.7 tree (`93a2e93ec`), so the engine serves
production's checkpoint, `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`. An image of this series serves that
checkpoint only: the routing width is a build-time constant and the config check refuses the FP4 checkpoint by name.

    ./apply.sh --check TREE     # both series apply, nothing written
    ./apply.sh TREE             # apply them

`RECORD.md` says what each patch carries and where its text comes from; `docs/INT4-PORT.md` has the scope, the
boot, the reply comparison against production and the speed tables.

## Serve settings for this checkpoint (measured 2026-11-14, image `int4d`)

The recipe's own environment plus:

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8      # the drafter's BF16 linears on MXFP8 (patch 0014)
    TF_FLASHNEXT_CONFIDENCE=-0.15       # draft while the drafts' probability product stays at 0.15 or more
    TF_FLASHNEXT_DRAFTS_GREEDY=15       # a greedy chain's depth at most
    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (patch 0015)

Drafts are proposals the verify keeps or rejects, so the settings move rounds, not replies: golden is 6/6 identical
to production's own serve with them, token hashes included. Aggregate tok/s prose / code, one fresh boot a cell, fp8
KV, 262,144 tokens (`~/work/int4/bench-best` on spark6):

| streams | with the settings | recipe defaults | production |
|---:|---|---|---|
| 1 | 71.4 / 125.6 | 67.3 / 110.7 | 71.2 / 129.5 |
| 2 | 99.5 / 161.7 | 93.9 / 156.9 | 119.8 / 180.8 |
| 4 | 141.7 / 226.5 | 140.5 / 227.4 | 165.1 / 259.4 |
| 6 | 175.1 / 277.3 | 166.2 / 267.7 | 210.3 / 328.2 |
| 8 | 189.0 / 314.8 | 184.7 / 308.4 | 242.4 / 380.0 |

The settings' column and the one- and four-stream defaults ran in one window (00:25 to 00:55 UTC); the other defaults
cells (2, 6 and 8 streams, with the same counters as the settings' cells) and production's 2 to 8 stream cells are
the evening's earlier windows (`bench-int4d`, `bench-int4b`).

The settings act at one stream (tokens a round 3.92 to 4.77 over the probe's prompts, production 4.50); from two
streams up the shared rounds' grants set the chains and the counters stay the defaults'. `TF_FLASHNEXT_GREEDY_WIDE=8`
adds 3% on code at six streams and 1% at eight. On the FP4 checkpoint `CONFIDENCE=-0.15` costs 6% on prose, so these
are settings of this checkpoint only.
