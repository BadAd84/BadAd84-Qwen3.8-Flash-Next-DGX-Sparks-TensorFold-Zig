# TensorFold 1.2.7 + INT4-AutoRound (experimental, not the accepted series)

Applied on top of `patches/1.2.7` (0001 to 0015) to a pristine v1.2.7 tree (`93a2e93ec`), so the engine serves
production's checkpoint, `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`. An image of this series serves that
checkpoint only: the routing width is a build-time constant and the config check refuses the FP4 checkpoint by name.

    ./apply.sh --check TREE     # both series apply, nothing written
    ./apply.sh TREE             # apply them

`RECORD.md` says what each patch carries and where its text comes from; `docs/INT4-PORT.md` has the scope, the
boot, the reply comparison against production and the speed table.
