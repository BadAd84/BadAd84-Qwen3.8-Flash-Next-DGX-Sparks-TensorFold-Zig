# KV dtype on the dev engine: what fp8 costs and what it buys

Window: spark6, one hold of `~/work/gpu.lock`, two arms, one fresh boot each, same image, same
checkpoint, everything else recorded (`work/kvdtype/out` on the box). Completed in 38 min:
`RUN-DONE ... elapsed 38 min`, then `RESTORED health 200 image
tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee... envcheck rc 0`. The lane that
ran it died while formatting this receipt, so the tables below are its own artefacts, copied here
verbatim: `replies-tables.md`, `speed-tables.md`, `run.log.excerpt`.

The two arms differ in one setting: `KV_DTYPE=bf16` (the launcher's default since 2026-11-24) against
`KV_DTYPE=fp8`. This is a single-lever measurement, and the engine's own help line (fp8 "about 1.84x the
pool of bf16 ... lossy, ~98.8% top-1 agreement") is quoted as the engine's claim, not as ours.

## Replies: the KV dtype alone moves them, on every prompt

At C=1 the arms differ on all five prompts, with identical prompt tokens on both sides and the same
completion length on four of the five:

| prompt | equal replies | first divergent token | bf16 tokens | fp8 tokens |
|---|---:|---:|---:|---:|
| code-1k | 0/1 | 389 | 512 | 512 |
| code-rec0 | 0/1 | 3 | 512 | 512 |
| prose-1k | 0/1 | 32 | 512 | 512 |
| prose-rec0 | 0/1 | 99 | 512 | 512 |
| prose-8k | 0/1 | 120 | 449 | 407 |

At the divergence the two arms hold different ids, e.g. code-1k token 16 against 17, code-rec0 464
against 12237, prose-1k 4779 against 7289. The code-1k pair is a near-tie flip (16 against 17 at the
same position), which is the shape the parity window's mid-text finding predicted. Prompt ids are equal
on both arms (`prose-8k 7997` against `7997`), so the difference is entirely in the computation.

## What fp8 buys at this shape, and what it costs

| level | kind | bf16 agg | bf16 per stream | fp8 agg | fp8 per stream | fp8/bf16 |
|---:|---|---:|---:|---:|---:|---:|
| 2 | prose | 102.1 | 51.03 | 100.0 | 50.02 | 0.979 |
| 2 | code | 170.6 | 85.30 | 169.0 | 84.48 | 0.991 |
| 4 | prose | 155.7 | 40.06 | 154.9 | 40.33 | 0.995 |
| 4 | code | 245.9 | 62.53 | 240.5 | 61.72 | 0.978 |
| 8 | prose | 220.2 | 27.11 | 213.4 | 26.96 | 0.969 |
| 8 | code | 337.4 | 42.58 | 328.5 | 41.43 | 0.974 |

Geometric mean over the eight aggregate cells: **0.988**, so fp8 is 1.2 percent slower at this shape, not
faster. Cold TTFT: 32k `0.995`, 8k `0.952`, warm turn `0.906`.

Capacity, from each arm's own boot plan (`plan.txt`, C=1):

| arm | page | per token | pool at boot |
|---|---:|---:|---|
| bf16 | 120.25 MiB | 30.06 KiB | 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 percent) |
| fp8 | 73.75 MiB | 18.44 KiB | 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 percent) |

So at this shape fp8 buys **1.63x** the page capacity, not the help line's 1.84x, and the pool in the
plan is the same 673.39 MiB on both arms.

## Why this is in the receipts

It is the disclosure behind PR #4183's divergence question: the arm that differed from production was on
fp8 KV against production's argv on fp8 and its banner on bf16, and fp8 is declared lossy by the engine's
own help. This measurement replaces that declaration with our own numbers at our own shape, and it is why
the dev arm now defaults to bf16 for the rest of the campaign's development work.
