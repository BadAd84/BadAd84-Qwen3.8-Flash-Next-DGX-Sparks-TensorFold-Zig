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
