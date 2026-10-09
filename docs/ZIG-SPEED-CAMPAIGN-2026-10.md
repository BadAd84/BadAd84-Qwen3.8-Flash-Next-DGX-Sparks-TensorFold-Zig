# Speed campaign on the recipe's Zig release (spark6), October 2026

The recipe's release 1.0.0 (main @ `364f21a`: TensorFold's Zig engine `db281878` + the recipe's 9 patches, the
INT4-AutoRound checkpoint, FP8 KV, image `tensorfold-qwen38:zig-db28187`) profiled and sped up on spark6
(2026-10-08, owner-directed). Every speed claim is an interleaved HTTP A/B through the recipe's own server
(`scripts/qwen38/zig/zqueue.sh`: one boot and one `qf_run.py` decode pass an arm per cycle, the arm order reversed each
cycle) with golden replies byte-identical to the stock image (`zgold_cmp.py`: 6/6 in every exact arm and cycle).
Greedy, thinking off, 512-token replies, per-request tok/s from the client side (`zig_sum.py`).

## Result (2026-10-08 ~22:15)

Stock image against `zots5` (`ots0101` + `ots0102` + `ots0104`, `TF_FLASHNEXT_MTP_FP8` on, `TF_FLASHNEXT_CONFIDENCE=-0.15`),
medians of the pass medians; replies byte-identical:

| | stock Zig release | OTS | change |
|---|---:|---:|---:|
| code, 1 / 2 / 4 clients | 104.6 / 76.1 / 52.5 | 118.5 / 85.2 / 59.2 | +13 / +12 / +13% |
| prose, 1 / 2 / 4 clients | 62.3 / 50.7 / 37.3 | 68.4 / 55.0 / 38.6 | +10 / +8 / +3% |

Against our Python production on spark4 (the two-box table in `scripts/qwen38/README.md`: code 92.6 / 65.1 / 42.8,
prose 76.1 / 52.1 / 33.0): code 1.28 / 1.31 / 1.38x, prose 0.90 / 1.06 / 1.17x.

## Merged image `zmerge1` (2026-10-09 ~14:00): the overnight lanes' winners

`scripts/qwen38/zig/merge/zmerge1-w1-w2-w4.patch` (over branch `up` = recipe + 0010 + 0011; with `ots0104`) =
W1 n-gram host gather (w1-fable `ngram-host.patch`), W2 copy windows (w2-fable `w2-wide-window.patch`), W4 batched
draft draws (w4-fable `batch-draws-v2.patch`); applied cleanly in order. Served with `TF_FLASHNEXT_NGRAM_RANDOM=1
TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_NGRAM_PREFETCH=1 TF_FLASHNEXT_WINDOW=64` (+ the MTP FP8 overlay and -0.15).
Verified on spark6 (`merge/mverify.sh`, `mverify2.sh`; a discarded warm-up boot first, base / merged / merged / base):
golden 6/6 on every boot, decode rounds identical to base.

| | base (`zots5`) | merged | change |
|---|---:|---:|---:|
| verbatim copy (1 client) | 325-328 tok/s | 755-765 | 2.3x |
| one-word rewrite | 265-267 | 410 (538-540 with re-sync) | +54% (2.0x) |
| cold prefill 8k, new text | 1,167 / 1,941 | 2,818 / 2,904 | 1.5-2.4x |
| cold prefill 32k, new text | 1,741 / 2,307 | 2,861 / 2,867 | 1.25-1.6x |
| code decode 1 / 2 / 4 clients | 118.1 / 84.2 / 54-58 | 117.9 / 85.1 / 59.4 | equal |
| prose decode 1 / 2 / 4 clients | 67.9 / 54.7 / 38.0 | 67.9 / 54.6 / 38.7 | equal |

Copy re-sync (`TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_MISS=keep`) doubles rewrites but
costs code decode 3.6-3.9% at one client even gated (`_RESYNC_KEPT=4` or `_RESYNC_TRIES=1`): OFF by default,
opt-in for edit-heavy agents. W4's gain (+1-2.7% at 4-8 clients) is below this hold's noise at 4 clients.

## Merged image `zmerge2` (2026-10-09 ~14:45): + W3 graph pooling

`scripts/qwen38/zig/merge/zmerge2-w1-w2-w3-w4.patch` = zmerge1 + w3-opus `pool-lru-v5.patch` (pooled sequences keep
their graphs across requests, graphs warmed at boot, LRU multi-graph table). Served with zmerge1's settings plus
`TF_FLASHNEXT_SEQ_POOL=4 TF_FLASHNEXT_WARM_POOL=4 TF_FLASHNEXT_SOLO_MAX=1024 TF_FLASHNEXT_MULTI_LRU=1
TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1`. Verified (`merge/mverify3.sh`: warm-up, then base / m1 / m2 /
m2 / m1 / base): golden 6/6 on all 7 boots, decode rounds and acceptance equal to base.

| | base (`zots5`) | zmerge1 | zmerge2 |
|---|---:|---:|---:|
| code decode 1 / 2 / 4 clients | 117.8 / 84.5 / 58.8 | 117.6 / 85.3 / 59.5 | 121.4 / 86.7 / 59.4 |
| prose decode 1 / 2 / 4 clients | 67.7 / 54.6 / 38.4 | 68.0 / 55.0 / 38.5 | 69.2 / 55.6 / 38.9 |
| 12 short (100-token) replies, total s | 17.81 / 17.32 | 17.70 / 16.98 | 16.22 / 16.64 |
| cold prefill 8k / 32k, new text | 1,229-1,613 / 2,034-2,136 | 2,827-2,900 / 2,852-2,877 | 2,889-2,914 / 2,871-2,875 |
| free RAM after boot | 14-19 GiB | 19-22 GiB | 18-19 GiB |

## Merged image `zmerge3` (2026-10-09 ~16:15): + W8 fused FP8 split-K + lm_head MT2 + W5 up-mix at decode

`scripts/qwen38/zig/merge/zmerge3.patch` = zmerge2 + w8-opus `w8v4.patch` (split-K FP8 projections with N >= 2048 on
one block a 64-column tile walking the 8 K slices in slice order: the cluster kernel's sum; lm_head in 32-row items)
+ w5-opus `pf5.patch` (`_hc_up_mix` at decode widths; its L2 prefetch stays off). Extra settings:
`TF_FLASHNEXT_W8_QMMF_FUSE=4 TF_FLASHNEXT_W8_QMMF_FUSE_N=2048 TF_FLASHNEXT_W8_HEAD_MT=2 TF_FLASHNEXT_UPMIX_DECODE=1`
(boot log: `ots w8: ...`). Verified (`merge/mverify4.sh`: warm-up, m2 / m3 / m3 / m2): golden 6/6 every boot.

| | zmerge2 | zmerge3 |
|---|---:|---:|
| code decode 1 / 2 / 4 clients | 122.0 / 85.7 / 57.3 | 122.9 / 88.1 / 62.1 |
| prose decode 1 / 2 / 4 clients | 68.9 / 55.3 / 38.5 | 68.9 / 55.9 / 39.6 |
| verbatim copy / one-word rewrite | 759-769 / 416-420 | 818-821 / 437-438 |

## Stop-rule shootout and `zmerge4` (2026-10-09 ~20:10)

Three exact drafting changes on zmerge3, one hold (`merge/mverify5.sh`: warm-up, then base / fable / opus / glm /
glm / opus / fable / base), golden 6/6 on all 9 boots:

| | zmerge3 | w6-fable propose floor | prose-glm calibrated `cum` T 0.25 | w6-opus split lines + int4 draft head |
|---|---:|---:|---:|---:|
| code 1 / 2 / 4 clients | 122.2 / 87.9 / 62.0 | 122.1 / 87.5 / 61.6 | 122.6 / 82.9 / 61.7 | 127.7 / 89.1 / 63.5 |
| prose 1 / 2 / 4 clients | 69.5 / 55.9 / 39.4 | 71.8 / 58.7 / 39.5 | 68.9 / 57.9 / 39.6 | 72.1 / 59.8 / 39.6 |

KEEP w6-opus (`w6d.patch`: the draft head reads the int4 lm_head's own columns, 105 MB a step; a draft is proposed
while the running product is >= 0.05 and the head runs another level while it is >= 0.20; depth capped at 7 while 2+
streams draft). DROP the other two (the calibrated `cum` rule's offline replay, +6.5%, did not hold live).

`zmerge4` = zmerge3 + w6-opus (conflicts with W1/W2/W4 resolved by `merge/resolve_opus.py`) + w2-fable
`resync-prompt-only.patch` (copy re-sync armed only when the copied source is in the prompt: no prose/code cost), patch
`scripts/qwen38/zig/merge/zmerge4.patch`. Extra settings: `TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_W6_TP=0.05
TF_FLASHNEXT_W6_TC=0.20 TF_FLASHNEXT_W6_CAP2=7 TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RAMP=jump
TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1`. Verified (`merge/mverify6.sh`: warm-up, m3 / m4 / m4 /
m3), golden 6/6 every boot:

| | zmerge3 | zmerge4 |
|---|---:|---:|
| code 1 / 2 / 4 clients | 122.1 / 87.4 / 61.5 | 127.3 / 88.5 / 63.1 |
| prose 1 / 2 / 4 clients | 69.5 / 55.7 / 39.0 | 71.6 / 59.5 / 39.4 |
| copy / one-word rewrite | 811-812 / 432-434 | 814-816 / 578-585 |
| cold prefill 8k / 32k | 2,886-2,917 / 2,810-2,871 | 2,894-2,913 / 2,774-2,843 |

## 1. Where the time goes

Instruments (`scripts/qwen38/zig/prof/`): the engine's own `tensorfold bench-many --served` with
`TF_FLASHNEXT_PROFILE=1` (rounds by part, eager) and `TF_FLASHNEXT_COUNT_EXPERTS=1`; nsys with `--cap-add SYS_ADMIN`
and `-t cuda-sw` (hardware tracing drops every kernel timestamp on this box: "incomplete CUPTI events dropped");
`--cuda-graph-trace=graph` for the GPU's busy share with graphs on; `zcheck.sh` for the engine's offline kernel checks.

- **GPU busy 96% with graphs on** at 1 and 4 streams (`nbusy.py`): host and launch gaps are not a lever.
- **One stream, prose (a round ~40 ms, 2.6 tokens):** FP8 dense matmuls (`qmmf`) 39% at ~230 GB/s (the roofline);
  bf16 matmuls 22%, of which the hyper-connections' down/up are ~6 ms a round at the bf16 roofline (the checkpoint keeps
  them bf16); int4 experts 22% (~11 distinct experts a layer); the MTP head ~12% (its layer was bf16).
- **Four streams (a round ~55-63 ms):** int4 experts 32% (33-40 distinct experts a layer), the MTP head ~15%, the
  DeltaNet tree kernel ~5% (reads and writes the 48 heads' fp32 states at ~300 GB/s, cache-assisted: no headroom).
- **Prefill (2,900 rows/s at 8k and 32k, `bench --tokens-file`):** a 2,048-row chunk takes ~707 ms: FP8 projections
  ~181 ms (~64 TFLOPS of bf16 MMA), experts 164 ms, attention 79 ms (grows with the context), hyper-connection glue
  ~140 ms (write-back + norm ~76% of its bandwidth roofline). No single waste.

## 2. Changes (patches in `scripts/qwen38/zig/patches/`, image by `build_zig_ots.sh`, overlay by `mtp_fp8.py`)

| Change | Measured (HTTP A/B) | Status |
|---|---|---|
| `TF_FLASHNEXT_CONFIDENCE` (the running-product stop rule, applied at <= 2 live streams; recipe -0.4, tuned at TP=2) | -0.3 beat -0.4 in every cell; -0.1 prose +8% at 1 and 2 clients; -0.15 best balance (3 boots an arm, with the patches: code +3-4% over -0.1, prose -2%) | keep -0.15 |
| `ots0101`: argmax and logsumexp-max rows on 1024 threads (one block a row; 256 threads read a 248k row at ~8 GB/s). The picks are a total order, so the same results | +0.5-1% in every cell | keep |
| `ots0102` + `mtp_fp8.py`: the MTP layer's bf16 linears (attention q/k/v/o, hyper-connections, mixer) on block FP8 (`TF_FLASHNEXT_MTP_FP8=DIR`, an overlay opened before `fast-fp8/`). The head only drafts: replies unchanged; acceptance unchanged (rounds within boot noise) | with 0101: code +5.9 / +5.1 / +5.5%, prose +2.7 / +3.2 / +1.6% at 1 / 2 / 4 clients | keep |
| `ots0104`: the boot's measured cost tables on stdout (`costs:` lines; `zarm.sh` records them) | diagnostic; the window costs agree within ~1% across 12 boots | keep |
| Rebuild control (`zctl`: the same source rebuilt by `build_zig_ots.sh`) | equal to the stock image in every cell | - |

## 2b. Candidates: small, proven only when repeated (each is free once proven)

- **`TF_FLASHNEXT_PREFILL_ROWS=4096`** (the engine says any chunking gives the same bits; the bench's reply shas
  agree). Offline (`bench`, `zots5`): 8k +1.5%, 32k +2.1% in both pairs of runs. Through HTTP (`zarm2.sh`, cold prompts,
  two boots an arm, 2026-10-08): 128k 2,622 / 2,622 tok/s against 2,571 / 2,586 (+1.4%, every 4096 boot above every
  2048 boot), 32k 2,848 / 2,867 against 2,727 / 2,853 (+0.5%, inside the boot spread), 8k no change. Copy and rewrite
  replies unchanged. Open: more boots at 32k-128k and the startup estimate at the default 8 streams.

## 3. Measured negatives

- **int4 expert kernels** (`int4-check` offline): 235-277 GB/s at 1-32 rows; 3 or 4 stages of loads in flight are
  slower than the shipped 2 (and the head runs at 244-260 GB/s). DROP.
- **`TF_FLASHNEXT_WIDE_CONFIDENCE`** (patch dropped): the per-draft rule above 2 streams at 0.4 / 0.6 against 0.5:
  within noise. DROP.
- **`TF_FLASHNEXT_PRODUCT_STREAMS=4`** (the product rule at 4 streams): code at 4 clients 54.8 -> 49.0. DROP.
- **`TF_FLASHNEXT_INT4AR_FAST=1`** (lossy: the main model's hyper-connections on the checkpoint's block FP8): code
  -7% at 1 client, prose +7% (noisy), and 7 of 8 greedy replies differ from the exact model within their first 4%
  (`zdiverge.py`). DROP.
- Code at 4 clients swung 49-60 tok/s between boots of one arm in the first sweeps; with `ots0104`'s logs the
  measured cost tables proved stable, and the last 6 boots stayed within 57-60.
