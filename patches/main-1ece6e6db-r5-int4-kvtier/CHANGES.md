# `main-1ece6e6db-r5-int4-kvtier`: what it changes against the packages it composes

No source line is written here that is not in one of the four packages: the five patches are those packages' patches,
byte for byte, with the tier's and the pool's numbers moved after the INT4 pair. This file records what the
composition changes in behaviour, and which of the recorded numbers still apply to the arm it builds.

## Against `patches/main-1ece6e6db-r5-int4` (the INT4 pair alone)

The arm gains a persistent KV tier: an fp8-capable state image (`0023`), an append that keeps one state rather than
two where the rewind applies (`0024`), and a plan-time refusal so the tier cannot be inert (`0025`).

The tier's recorded numbers were measured on a different checkpoint. The two tier windows (`kv-w1`, `kv-dedup`) ran
the NVFP4 checkpoint with fp8 KV at one slot of 262,144 tokens; this directory serves the INT4-AutoRound checkpoint at
eight streams of 262,144 tokens. So the tier's published figures are evidence that the tier works and that the dedup
halves the write, not a prediction of this arm's numbers:

| measured, on the NVFP4 arm at one 262,144-token slot | figure |
|---|---|
| the fp8 image's first state | 6,813 tokens, 232 MiB, 294 ms write; read back 232 MiB in 76 ms |
| a resumed prefill against a cold one | 0.113 s against 2.947 s (0.195 s ttft against 2.952 s) |
| an append turn's bytes, dedup on against off | 115.1 MiB against 228.1 MiB (turns under `min_gap`) |
| a 60 GiB budget's append turns | 508 against 257 |
| exactness | five of five resumed replies equal their no-tier cold twins' token ids |

At eight streams of 262,144 tokens the plan behaves differently, and that is where the pool's refusal comes from: the
pages are sized first and leave the prompt cache zero, so the tier would write and resume nothing with the flag
accepted. The INT4 shape is exactly where that was measured (`no prompt cache` beside `389 pages of 4096 rows`,
2026-11-19). `0025` refuses that shape by name.

## Against `patches/main-1ece6e6db-r5-kvtier` (the tier alone)

The arm gains the INT4 port: production's checkpoint admitted and served by this engine, with the GPTQ reader read
through main's `core.quant.gptq` (#3611), the port's own tests collected under
`zig build -Dfixed-cpu test-flashnext-int4-host`, and four settings read through `platform/environment.zig`. The
routing widths are build-time constants (`slots = 6`, `shared_w = 1280`), so the image serves this checkpoint and
refuses the FP4 one by name. `patches/main-1ece6e6db-r5-int4/CHANGES.md` names every text difference from the r2-int4
package and the one hand-resolved conflict (`cuda_batch_hc.zig`'s `writebackNorm` shared-direct branch, r4's
writeback-with-normalize call and the INT4 `slots - 1, slots` widths kept together).

The tier's own code is untouched by that port: the two packages meet at `cuda.zig` (the port's loader arm and the
tier's store creation are separate blocks) and at the FP8 split of the checkpoint's experts, which the INT4 port keeps
as its own loader arm. The gate run is what proves it: five patches apply in order, the file counts are the INT4
package's base plus the tier's and the pool's files, and every test step of both packages passes on the result.

## What the composition does not change

- No setting is added: `platform/environment.zig` and `docs/environment.md` are the INT4 package's; the tier's and the
  pool's patches add none.
- The INT4 port's gap against the maintainer's approved six steps on issue #3368 is unchanged, including the MTP
  layer recoded to block FP8 at load (drafts only, replies exact) and the missing float64 fidelity cells. That gap is
  the INT4 package's to close, not this directory's.
- The tier's missing pieces are unchanged: the staging ring (design item 8), a store pin (9) and the block-name
  lineage (10). A state above the 1 GiB staging permit is skipped as `StagingFull`; `0023` declares `context` so the
  permit is priced at the window, which is what makes a 262,144-token cell testable at all.

## The trailing gate rows

The two steps that closed after this directory's first commit, from the same gate run: `GATE nvcc_fatbins
rc=0 wall=711s` (`327/327 steps succeeded`, `FATBIN fn_int4: 1132920 bytes`, `FATBIN images 125`) and
`GATE test_cuda_cache_budget rc=0 wall=0s` (`6/6 steps succeeded; 21/21 tests passed`). The pool patch, `0025` here
and `0023` in its own package, is the one the witness belongs to: the step reads 19 tests without it and 21 with it,
and a planted false assertion fails the step by name. The run's own `new_test_ran` grep was blind to a passing
test's name, which is why it read red; the check is replaced in `work/KvTierShip/gates.sh`. `RECORD.md` carries the
two rows verbatim and the counts.
