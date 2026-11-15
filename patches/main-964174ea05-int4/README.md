# TensorFold main-964174ea05 + INT4-AutoRound (experimental, not the accepted series)

Applied on top of `patches/main-964174ea05` (0001 to 0019) to a pristine checkout of upstream main at
`964174ea05879e6dde1de1198a3aae3ef8b46a3b` (v1.2.9-33-g964174ea05), so the engine serves production's checkpoint,
`azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`. An image of this series serves that checkpoint only: the
routing width is a build-time constant and the config check refuses the FP4 checkpoint by name.

    ./apply.sh --check TREE     # both series apply, nothing written
    ./apply.sh TREE             # apply them

STATUS: re-seated on 2026-11-15 against `964174ea05`; `compile-config-server` passes on spark6 (rc 0), but it is NOT yet built into an image or served; the receipts in
`docs/INT4-PORT.md` are the 1.2.7 series' (`patches/1.2.7-int4`, image `int4d`). Two hunks needed a decision, both
recorded in `RECORD.md`: the BF16-expert recode stays beside upstream's shared block-FP8 reader, and the scratch
estimate keeps upstream's extra slot row.

`RECORD.md` says what each patch carries and where its text comes from; `docs/INT4-PORT.md` has the scope, the boot,
the reply comparison against production and the speed tables, all measured on the 1.2.7 series.

## Serve settings for this checkpoint (measured 2026-11-14 on 1.2.7, image `int4d`)

The recipe's own environment plus:

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8      # the drafter's BF16 linears on MXFP8 (patch 0014)
    TF_FLASHNEXT_CONFIDENCE=-0.15       # draft while the drafts' probability product stays at 0.15 or more
    TF_FLASHNEXT_DRAFTS_GREEDY=15       # a greedy chain's depth at most
    TF_FLASHNEXT_SHARED_DRAFTS=0        # shared rounds keep that rule instead of 0.6 a draft
    TF_FLASHNEXT_GREEDY_WIDE=8          # 6 and 8 streams keep the depth
    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (patch 0015)
