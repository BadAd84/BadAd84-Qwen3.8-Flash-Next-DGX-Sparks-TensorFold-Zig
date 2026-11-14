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
    TF_FLASHNEXT_SHARED_DRAFTS=0        # shared rounds keep that rule instead of 0.6 a draft
    TF_FLASHNEXT_GREEDY_WIDE=8          # 6 and 8 streams keep the depth
    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (patch 0015)

Drafts are proposals the verify keeps or rejects, so the settings move rounds, not replies: golden is 6/6 identical
to production's own serve with them, token hashes included, and every multi-stream decode reply's sha equals the one
without `SHARED_DRAFTS=0`. Aggregate tok/s prose / code, one fresh boot a cell, fp8 KV, 262,144 tokens (spark6
`~/work/int4/bench-best` for one stream, `bench-sh` for two to eight):

| streams | with the settings | recipe defaults | production | settings / production |
|---:|---|---|---|---|
| 1 | 71.4 / 125.6 | 67.3 / 110.7 | 71.2 / 129.5 | 1.00 / 0.97 |
| 2 | 109.4 / 169.7 | 93.9 / 156.9 | 119.8 / 180.8 | 0.91 / 0.94 |
| 4 | 151.6 / 239.6 | 140.5 / 227.4 | 164.7 / 261.9 | 0.92 / 0.91 |
| 6 | 186.1 / 297.1 | 166.2 / 267.7 | 210.3 / 328.2 | 0.88 / 0.91 |
| 8 | 199.0 / 340.1 | 184.7 / 308.4 | 242.4 / 380.0 | 0.82 / 0.89 |

The one-stream cells ran in one window (`bench-best`, 00:25 to 00:55 UTC); the settings' two to eight stream cells
and production at four streams in another (`bench-sh`, 00:58 to 01:19); the four-stream defaults are `bench-best`'s,
the other defaults and production cells the evening's earlier windows (`bench-int4d`, `bench-int4b`).
On the FP4 checkpoint `CONFIDENCE=-0.15` costs 6% on prose, so these are settings of this checkpoint only.
