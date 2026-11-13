# Speed target: the zmerge8-kfix production serve, measured 2026-11-10

This branch is upstream TensorFold v1.2.6 (`6e9af9302`) plus this one document. The document records the speed
every 1.2.6 lever is ranked against: the production serve on spark6 (image
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, the recipe's Zig 1.0.0 stack with our OTS 0010-0028,
tfm-fixes, tfm-warm-t and c68-shared-cost-levels, plus its two kindling boot fixes in the base image) ran the
full suite once, one fresh boot per concurrency level, and the numbers below are its cells.

**Model note (added 2026-11-13):** this serve's checkpoint, azampatti's INT4-AutoRound, routes **5 experts a token**
(`num_experts_per_tok` 5, shared expert 1280 wide); the campaign's `main` serves nvidia's FP4 checkpoint, which routes
**10** (shared expert 640 wide), over the same 512 experts of width 640. A decode round here reads about 2.35 times
fewer expert bytes at one stream (measured by expert id, campaign `docs/CATCHUP-1.2.6.md`), so a cell measured on the
other checkpoint compares a different model configuration, not only a different engine.

A change ships when the cell it targets moves toward these numbers and no other cell regresses. A faster
decode cell that costs TTFT, a higher aggregate that costs the per-stream rate, or a win at 6 streams that
loses at 1 are trades, and a trade is the owner's call.

## How the cells were measured

- Boot: the production start path per cell (`~/qwen6-start.sh`'s env, `PARALLEL=C` bound to `127.0.0.1`, warm
  turns off, INT4-AutoRound, fp8 KV, 262,144-token windows), a fresh boot for every concurrency level; boot
  time from the start call to the health check, sequence memory and the golden line from the boot log.
- Decode: every slot busy, greedy, 512 tokens a request, distinct prompts with a per-pass nonce so nothing is
  cached, prose then code, three passes. Aggregate is the sum of the per-request rates; the bracket is the
  per-stream median. The second table is all completion tokens over the batch's wall time.
- TTFT: client-measured to the first streamed content token, cold prompts of 1k, 8k, 32k and 120k tokens,
  thinking off and on, two reps, medians. Each level is measured idle and with C-1 other streams decoding; the
  bracket in the table is that under-load value.
- Warm turn: a kept 100k conversation plus a 2k addition at the same loads. The production serve runs warm
  turns off, so this is the plain next turn (prompt-cache reuse, no background prefill).
- Golden 6/6 on every boot; `/health` request counts before and after each probe; GPU temperature and clocks at
  every window; sparkDash stopped and no other client reached the serve for the window.
- Driver and summariser: `scripts/qwen38/zig/target/target_queue.sh` and `target_sum.py` of the campaign repo
  (qwen3.8-flash-next-dev); raw cells under spark6 `~/work/target/runs/`.

## Decode, aggregate tok/s (per-stream median in brackets), median of 3 passes

| concurrency | prose | code |
|---|---|---|
| 1 | 70.9 (70.9) | 113.0 (113.0) |
| 2 | 103.3 (51.6) | 173.7 (86.8) |
| 4 | 162.3 (41.2) | 254.0 (63.6) |
| 6 | 202.2 (34.8) | 311.8 (52.9) |
| 8 | 237.1 (30.1) | 370.5 (46.5) |

## Decode, tokens per wall second

| concurrency | prose | code |
|---|---|---|
| 1 | 69.9 | 111.4 |
| 2 | 99.5 | 169.0 |
| 4 | 152.2 | 226.9 |
| 6 | 186.7 | 282.9 |
| 8 | 214.2 | 327.3 |

## Cold TTFT (s, median of 2 reps; the bracket is the same level with C-1 streams decoding)

| case | C=1 | C=2 | C=4 | C=6 | C=8 |
|---|---|---|---|---|---|
| 1k, thinking off | 0.420 | 0.568 (0.499) | 0.494 (0.519) | 0.412 (0.940) | 0.434 (0.524) |
| 1k, thinking on | 0.442 | 0.486 (0.514) | 0.479 (0.504) | 0.438 (0.495) | 0.470 (0.543) |
| 8k, thinking off | 2.649 | 2.748 (2.782) | 2.736 (2.796) | 2.628 (2.744) | 2.713 (2.804) |
| 8k, thinking on | 2.729 | 2.915 (2.817) | 2.900 (2.833) | 2.798 (2.902) | 2.680 (2.902) |
| 32k, thinking off | 10.768 | 10.994 (10.870) | 10.890 (10.901) | 10.832 (10.909) | 10.825 (11.040) |
| 32k, thinking on | 10.720 | 10.793 (10.925) | 10.787 (11.055) | 10.857 (11.082) | 10.918 (11.114) |
| 120k, thinking off | 42.759 | 42.879 (42.719) | 43.132 (42.918) | 42.837 (42.816) | 42.975 (42.944) |
| 120k, thinking on | 42.651 | 42.966 (42.984) | 42.850 (42.976) | 42.946 (43.070) | 42.873 (43.124) |
| warm +2k on a kept 100k | 1.403 | 1.282 (1.385) | 1.372 (1.329) | 1.268 (1.294) | 1.366 (1.225) |

The 1k C=6 off cell's under-load value (0.940) is a single warm sample; its thinking-on twin at the same level
is 0.495 and every other 1k cell is 0.41 to 0.54, so read it as noise rather than a load effect.

## Boot and memory

| concurrency | boot s | sequence memory | golden |
|---|---|---|---|
| 1 | 83 | 26.43 GiB (38.43 free, 10.0 kept free); fp8 KV, 1056 bytes a position a layer | 6/6 |
| 2 | 87 | 25.27 GiB (37.27 free, 10.0 kept free) | 6/6 |
| 4 | 90 | 26.07 GiB (38.07 free, 10.0 kept free) | 6/6 |
| 6 | 90 | 25.00 GiB (37.00 free, 10.0 kept free) | 6/6 |
| 8 | 90 | 24.14 GiB (36.14 free, 10.0 kept free) | 6/6 |

## RigMark (the same serve, one comparison id, reasoning effort low)

| workload | tok/s | range | gate |
|---|---|---|---|
| prose | 60.3 | 57.2 to 129.9 | 4/5 |
| code | 113.4 | 108.0 to 120.2 | 5/5 |
| structured | 157.9 | 153.7 to 165.6 | 5/5 |

Prefill, cold: 8k 3,213 tok/s (2.55 s), 32k 3,034 tok/s (10.80 s), 64k 2,979 tok/s (22.00 s); an immediate
replay takes 0.00, 0.02 and 0.04 s. Capped concurrent generation: aggregate 75.8 tok/s at C1, 118.7 at C2,
185.7 at C4. 14 of 15 basic output gates passed; the one prose run that missed its gate is RigMark's own
output check, not a serve error. Receipt and card: spark6
`~/work/bench/rigmark/runs/prod-zmerge8-kfix-20261110T202112Z.{json,card.txt}`.

## Reading the table against a 1.2.6 stack

- The 1.2.6 stock arm cannot serve 6 or 8 streams at 262,144 tokens with bf16 KV (32.9 GiB of cache against
  31.4 free on this box), so stock cells run 131,072-token windows, and the fp8-KV lever (patches 0007-0011 of
  the campaign's 1.2.6 series) is what makes the 8-stream cell exist at all.
- v1.2.6's prompt cache is rebuilt for concurrent agents (#2699): at 16 agents on a GB10 a follow-up's median
  first token drops from 105 s to 25.8 s. The warm-turn row here is one kept conversation at 1 to 8 streams,
  not that measurement; a 1.2.6 stack is expected to beat the production serve on follow-up TTFT under load
  once its cache settings are retuned, and that is a target to confirm, not a claim in this table.
- Every cell is a target: reaching the production numbers at 1/2/4/6/8 with the reply shas equal to stock's
  makes the 1.2.6 stack substitutable, and beating them is the lever campaign's gain.
