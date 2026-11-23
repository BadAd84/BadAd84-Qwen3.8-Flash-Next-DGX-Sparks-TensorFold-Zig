# Knob receipt, final: every upstream setting that reaches the Flash Next CUDA serve

All three windows completed on spark6 (w1 16:03, w2 19:58, w3 21:05 UTC, each with `prod /health 200` in `out/<w>/production.txt`). Every number below is read from the fetched evidence under `box/out/`.

## Headline: the new one-stream chunk default

`TF_FLASHNEXT_CHUNK_SOLO` unset resolves to the larger of `TF_FLASHNEXT_CHUNK` and 8,192 rows on a server of one stream. Window 3 measured it at `--parallel 1`, cache off, two runs a side with cold TTFT medians of three a run:

| case | load | treatment | runs | ttft_s | base_ttft_s | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| p/cold2k-off | idle | EVICT | 0 |  | 0.972 |  | unmeasured |
| p/cold2k-off | idle | P_16384 | 2 | 0.966 | 0.972 | -0.51 | level |
| p/cold2k-off | idle | P_3072 | 2 | 0.976 | 0.972 | 0.51 | level |
| p/cold2k-off | idle | P_UNSET | 2 | 0.993 | 0.972 | 2.21 | slower |
| p/cold32k-off | idle | EVICT | 0 |  | 14.062 |  | unmeasured |
| p/cold32k-off | idle | P_16384 | 2 | 13.867 | 14.062 | -1.39 | faster |
| p/cold32k-off | idle | P_3072 | 2 | 15.029 | 14.062 | 6.88 | slower |
| p/cold32k-off | idle | P_UNSET | 2 | 14.197 | 14.062 | 0.95 | level |
| p/cold64k-off | idle | EVICT | 0 |  | 28.901 |  | unmeasured |
| p/cold64k-off | idle | P_16384 | 2 | 28.577 | 28.901 | -1.12 | faster |
| p/cold64k-off | idle | P_3072 | 2 | 30.722 | 28.901 | 6.3 | slower |
| p/cold64k-off | idle | P_UNSET | 2 | 29.229 | 28.901 | 1.14 | slower |
| p/cold8k-off | idle | EVICT | 0 |  | 3.427 |  | unmeasured |
| p/cold8k-off | idle | P_16384 | 2 | 3.405 | 3.427 | -0.63 | level |
| p/cold8k-off | idle | P_3072 | 2 | 3.678 | 3.427 | 7.31 | slower |
| p/cold8k-off | idle | P_UNSET | 2 | 3.446 | 3.427 | 0.55 | level |

- The base arm itself has the setting unset, so it IS the new default: `P_UNSET` (the same configuration) measures 0.95 to 2.21 percent from it, which is this window's noise floor.
- The old behaviour, `TF_FLASHNEXT_CHUNK_SOLO=3072`, is **6.30 to 7.31 percent slower** at 8k, 32k and 64k and level at 2k. The new default is therefore a genuine 6 to 7 percent gain over what we ran before, at equal tokens.
- 16,384 rows is a further 1.12 to 1.39 percent faster at 32k and 64k, and level at 2k and 8k, so the default leaves about 1 percent on the table at long prompts only.

## Window 1: chunk 1,536 and the fused read-out

| cell | treatment | runs | tps | base_tps | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| a/conc_t0/chat/0.0/1 | C1536 | 2 | 41.650000000000006 | 41.75 | -0.24 | level |
| a/conc_t0/chat/0.0/1 | F1 | 2 | 41.7 | 41.75 | -0.12 | level |
| a/conc_t0/chat/0.0/2 | C1536 | 2 | 86.15 | 86.55000000000001 | -0.46 | level |
| a/conc_t0/chat/0.0/2 | F1 | 2 | 86.55000000000001 | 86.55000000000001 | 0.0 | level |
| a/conc_t0/chat/0.0/4 | C1536 | 2 | 155.6 | 156.10000000000002 | -0.32 | level |
| a/conc_t0/chat/0.0/4 | F1 | 2 | 155.85 | 156.10000000000002 | -0.16 | level |
| a/conc_t0/chat/0.0/6 | C1536 | 2 | 209.6 | 210.5 | -0.43 | level |
| a/conc_t0/chat/0.0/6 | F1 | 2 | 210.65 | 210.5 | 0.07 | level |
| a/conc_t0/chat/0.0/8 | C1536 | 2 | 257.0 | 257.15 | -0.06 | level |
| a/conc_t0/chat/0.0/8 | F1 | 2 | 257.25 | 257.15 | 0.04 | level |
| a/conc_t0/code/0.0/1 | C1536 | 2 | 72.6 | 72.9 | -0.41 | level |
| a/conc_t0/code/0.0/1 | F1 | 2 | 72.8 | 72.9 | -0.14 | level |
| a/conc_t0/code/0.0/2 | C1536 | 2 | 137.4 | 137.25 | 0.11 | level |
| a/conc_t0/code/0.0/2 | F1 | 2 | 137.85 | 137.25 | 0.44 | level |
| a/conc_t0/code/0.0/4 | C1536 | 2 | 241.85 | 243.0 | -0.47 | level |
| a/conc_t0/code/0.0/4 | F1 | 2 | 242.25 | 243.0 | -0.31 | level |
| a/conc_t0/code/0.0/6 | C1536 | 2 | 306.25 | 307.45000000000005 | -0.39 | level |
| a/conc_t0/code/0.0/6 | F1 | 2 | 306.85 | 307.45000000000005 | -0.2 | level |
| a/conc_t0/code/0.0/8 | C1536 | 2 | 370.25 | 373.04999999999995 | -0.75 | level |
| a/conc_t0/code/0.0/8 | F1 | 2 | 371.55 | 373.04999999999995 | -0.4 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | C1536 | 2 | 72.78056604984386 | 73.0455554052425 | -0.36 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | F1 | 2 | 72.84422435426862 | 73.0455554052425 | -0.28 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | C1536 | 2 | 41.76141444110144 | 41.86538397178505 | -0.25 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | F1 | 2 | 41.810040174745566 | 41.86538397178505 | -0.13 | level |

| case | load | treatment | runs | ttft_s | base_ttft_s | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| b/cold2k-off | idle | C1536 | 2 | 1.067 | 0.989 | 7.88 | slower |
| b/cold2k-off | idle | F1 | 2 | 0.925 | 0.989 | -6.47 | faster |
| b/cold32k-off | idle | C1536 | 2 | 15.996 | 14.984 | 6.75 | slower |
| b/cold32k-off | idle | F1 | 2 | 14.405 | 14.984 | -3.86 | faster |
| b/cold64k-off | idle | C1536 | 2 | 33.017 | 30.545 | 8.09 | slower |
| b/cold64k-off | idle | F1 | 2 | 29.572 | 30.545 | -3.19 | faster |
| b/cold8k-off | idle | C1536 | 2 | 4.001 | 3.7 | 8.15 | slower |
| b/cold8k-off | idle | F1 | 2 | 3.548 | 3.7 | -4.11 | faster |

- `TF_FLASHNEXT_CHUNK=1536` loses: level on every decode cell, slower on all four cold TTFT cells by 6.75 to 8.15 percent.
- `TF_FLASHNEXT_READOUT_FUSED=1` wins: decode level, cold TTFT **faster** by 3.19 to 6.47 percent at 64k, 32k, 8k and 2k.

## Window 2: chunk 4,096 and 6,144, the diagnostics, the unset reserve

| cell | treatment | runs | tps | base_tps | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| a/conc_t0/chat/0.0/1 | C4096 | 2 | 41.75 | 41.55 | 0.48 | level |
| a/conc_t0/chat/0.0/1 | C6144 | 2 | 42.05 | 41.55 | 1.2 | faster |
| a/conc_t0/chat/0.0/1 | DEVCK | 2 | 41.65 | 41.55 | 0.24 | level |
| a/conc_t0/chat/0.0/1 | PRICE | 2 | 41.25 | 41.55 | -0.72 | level |
| a/conc_t0/chat/0.0/1 | RESERVE | 2 | 41.25 | 41.55 | -0.72 | level |
| a/conc_t0/chat/0.0/1 | S3072 | 2 | 41.5 | 41.55 | -0.12 | level |
| a/conc_t0/chat/0.0/2 | C4096 | 2 | 86.5 | 86.0 | 0.58 | level |
| a/conc_t0/chat/0.0/2 | C6144 | 2 | 86.80000000000001 | 86.0 | 0.93 | level |
| a/conc_t0/chat/0.0/2 | DEVCK | 2 | 86.30000000000001 | 86.0 | 0.35 | level |
| a/conc_t0/chat/0.0/2 | PRICE | 2 | 85.7 | 86.0 | -0.35 | level |
| a/conc_t0/chat/0.0/2 | RESERVE | 2 | 85.55000000000001 | 86.0 | -0.52 | level |
| a/conc_t0/chat/0.0/2 | S3072 | 2 | 85.9 | 86.0 | -0.12 | level |
| a/conc_t0/chat/0.0/4 | C4096 | 2 | 156.1 | 155.39999999999998 | 0.45 | level |
| a/conc_t0/chat/0.0/4 | C6144 | 2 | 156.5 | 155.39999999999998 | 0.71 | level |
| a/conc_t0/chat/0.0/4 | DEVCK | 2 | 155.60000000000002 | 155.39999999999998 | 0.13 | level |
| a/conc_t0/chat/0.0/4 | PRICE | 2 | 154.65 | 155.39999999999998 | -0.48 | level |
| a/conc_t0/chat/0.0/4 | RESERVE | 2 | 154.6 | 155.39999999999998 | -0.51 | level |
| a/conc_t0/chat/0.0/4 | S3072 | 2 | 155.1 | 155.39999999999998 | -0.19 | level |
| a/conc_t0/chat/0.0/6 | C4096 | 2 | 210.39999999999998 | 209.35000000000002 | 0.5 | level |
| a/conc_t0/chat/0.0/6 | C6144 | 2 | 210.85 | 209.35000000000002 | 0.72 | level |
| a/conc_t0/chat/0.0/6 | DEVCK | 2 | 209.55 | 209.35000000000002 | 0.1 | level |
| a/conc_t0/chat/0.0/6 | PRICE | 2 | 208.75 | 209.35000000000002 | -0.29 | level |
| a/conc_t0/chat/0.0/6 | RESERVE | 2 | 208.65 | 209.35000000000002 | -0.33 | level |
| a/conc_t0/chat/0.0/6 | S3072 | 2 | 208.85000000000002 | 209.35000000000002 | -0.24 | level |
| a/conc_t0/chat/0.0/8 | C4096 | 2 | 257.29999999999995 | 256.6 | 0.27 | level |
| a/conc_t0/chat/0.0/8 | C6144 | 2 | 257.9 | 256.6 | 0.51 | level |
| a/conc_t0/chat/0.0/8 | DEVCK | 2 | 257.20000000000005 | 256.6 | 0.23 | level |
| a/conc_t0/chat/0.0/8 | PRICE | 2 | 255.4 | 256.6 | -0.47 | level |
| a/conc_t0/chat/0.0/8 | RESERVE | 2 | 254.89999999999998 | 256.6 | -0.66 | level |
| a/conc_t0/chat/0.0/8 | S3072 | 2 | 255.8 | 256.6 | -0.31 | level |
| a/conc_t0/code/0.0/1 | C4096 | 2 | 72.85 | 72.5 | 0.48 | level |
| a/conc_t0/code/0.0/1 | C6144 | 2 | 73.44999999999999 | 72.5 | 1.31 | faster |
| a/conc_t0/code/0.0/1 | DEVCK | 2 | 72.44999999999999 | 72.5 | -0.07 | level |
| a/conc_t0/code/0.0/1 | PRICE | 2 | 72.1 | 72.5 | -0.55 | level |
| a/conc_t0/code/0.0/1 | RESERVE | 2 | 72.35 | 72.5 | -0.21 | level |
| a/conc_t0/code/0.0/1 | S3072 | 2 | 72.25 | 72.5 | -0.34 | level |
| a/conc_t0/code/0.0/2 | C4096 | 2 | 137.95 | 137.35000000000002 | 0.44 | level |
| a/conc_t0/code/0.0/2 | C6144 | 2 | 138.7 | 137.35000000000002 | 0.98 | level |
| a/conc_t0/code/0.0/2 | DEVCK | 2 | 137.7 | 137.35000000000002 | 0.25 | level |
| a/conc_t0/code/0.0/2 | PRICE | 2 | 136.35000000000002 | 137.35000000000002 | -0.73 | level |
| a/conc_t0/code/0.0/2 | RESERVE | 2 | 136.95 | 137.35000000000002 | -0.29 | level |
| a/conc_t0/code/0.0/2 | S3072 | 2 | 137.0 | 137.35000000000002 | -0.25 | level |
| a/conc_t0/code/0.0/4 | C4096 | 2 | 242.8 | 241.9 | 0.37 | level |
| a/conc_t0/code/0.0/4 | C6144 | 2 | 243.9 | 241.9 | 0.83 | level |
| a/conc_t0/code/0.0/4 | DEVCK | 2 | 241.9 | 241.9 | 0.0 | level |
| a/conc_t0/code/0.0/4 | PRICE | 2 | 240.39999999999998 | 241.9 | -0.62 | level |
| a/conc_t0/code/0.0/4 | RESERVE | 2 | 241.25 | 241.9 | -0.27 | level |
| a/conc_t0/code/0.0/4 | S3072 | 2 | 240.60000000000002 | 241.9 | -0.54 | level |
| a/conc_t0/code/0.0/6 | C4096 | 2 | 307.20000000000005 | 305.75 | 0.47 | level |
| a/conc_t0/code/0.0/6 | C6144 | 2 | 308.75 | 305.75 | 0.98 | level |
| a/conc_t0/code/0.0/6 | DEVCK | 2 | 307.1 | 305.75 | 0.44 | level |
| a/conc_t0/code/0.0/6 | PRICE | 2 | 305.20000000000005 | 305.75 | -0.18 | level |
| a/conc_t0/code/0.0/6 | RESERVE | 2 | 305.0 | 305.75 | -0.25 | level |
| a/conc_t0/code/0.0/6 | S3072 | 2 | 305.2 | 305.75 | -0.18 | level |
| a/conc_t0/code/0.0/8 | C4096 | 2 | 371.75 | 370.0 | 0.47 | level |
| a/conc_t0/code/0.0/8 | C6144 | 2 | 372.75 | 370.0 | 0.74 | level |
| a/conc_t0/code/0.0/8 | DEVCK | 2 | 371.05 | 370.0 | 0.28 | level |
| a/conc_t0/code/0.0/8 | PRICE | 2 | 368.4 | 370.0 | -0.43 | level |
| a/conc_t0/code/0.0/8 | RESERVE | 2 | 368.0 | 370.0 | -0.54 | level |
| a/conc_t0/code/0.0/8 | S3072 | 2 | 368.95 | 370.0 | -0.28 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | C4096 | 2 | 72.9251791626966 | 72.62398571738491 | 0.41 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | C6144 | 2 | 73.48545026817155 | 72.62398571738491 | 1.19 | faster |
| a/openai_t0/fibonacci-raw/0.0/1 | DEVCK | 2 | 72.76208135884309 | 72.62398571738491 | 0.19 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | PRICE | 2 | 72.11297243954809 | 72.62398571738491 | -0.7 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | RESERVE | 2 | 72.3895397549094 | 72.62398571738491 | -0.32 | level |
| a/openai_t0/fibonacci-raw/0.0/1 | S3072 | 2 | 72.7761137365143 | 72.62398571738491 | 0.21 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | C4096 | 2 | 41.935749771306405 | 41.67959264964674 | 0.61 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | C6144 | 2 | 42.117841839674256 | 41.67959264964674 | 1.05 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | DEVCK | 2 | 41.69946056703398 | 41.67959264964674 | 0.05 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | PRICE | 2 | 41.42406496215591 | 41.67959264964674 | -0.61 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | RESERVE | 2 | 41.56452228521343 | 41.67959264964674 | -0.28 | level |
| a/openai_t0/gpu-chat-no-think/0.0/1 | S3072 | 2 | 41.7069343607902 | 41.67959264964674 | 0.07 | level |

| case | load | treatment | runs | ttft_s | base_ttft_s | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- | --- |
| b/cold2k-off | idle | C4096 | 2 | 0.962 | 0.961 | 0.1 | level |
| b/cold2k-off | idle | C6144 | 2 | 0.955 | 0.961 | -0.62 | level |
| b/cold2k-off | idle | DEVCK | 0 |  | 0.961 |  | unmeasured |
| b/cold2k-off | idle | PRICE | 0 |  | 0.961 |  | unmeasured |
| b/cold2k-off | idle | RESERVE | 0 |  | 0.961 |  | unmeasured |
| b/cold2k-off | idle | S3072 | 2 | 0.974 | 0.961 | 1.3 | level |
| b/cold32k-off | idle | C4096 | 2 | 14.41 | 14.971 | -3.74 | faster |
| b/cold32k-off | idle | C6144 | 2 | 14.258 | 14.971 | -4.77 | faster |
| b/cold32k-off | idle | DEVCK | 0 |  | 14.971 |  | unmeasured |
| b/cold32k-off | idle | PRICE | 0 |  | 14.971 |  | unmeasured |
| b/cold32k-off | idle | RESERVE | 0 |  | 14.971 |  | unmeasured |
| b/cold32k-off | idle | S3072 | 2 | 15.026 | 14.971 | 0.36 | level |
| b/cold64k-off | idle | C4096 | 2 | 29.742 | 30.642 | -2.94 | faster |
| b/cold64k-off | idle | C6144 | 2 | 29.139 | 30.642 | -4.9 | faster |
| b/cold64k-off | idle | DEVCK | 0 |  | 30.642 |  | unmeasured |
| b/cold64k-off | idle | PRICE | 0 |  | 30.642 |  | unmeasured |
| b/cold64k-off | idle | RESERVE | 0 |  | 30.642 |  | unmeasured |
| b/cold64k-off | idle | S3072 | 2 | 30.721 | 30.642 | 0.26 | level |
| b/cold8k-off | idle | C4096 | 2 | 3.521 | 3.67 | -4.06 | faster |
| b/cold8k-off | idle | C6144 | 2 | 3.509 | 3.67 | -4.4 | faster |
| b/cold8k-off | idle | DEVCK | 0 |  | 3.67 |  | unmeasured |
| b/cold8k-off | idle | PRICE | 0 |  | 3.67 |  | unmeasured |
| b/cold8k-off | idle | RESERVE | 0 |  | 3.67 |  | unmeasured |
| b/cold8k-off | idle | S3072 | 2 | 3.681 | 3.67 | 0.27 | level |

## Window 3: eviction and the one-stream arms

| cell | treatment | runs | tps | base_tps | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- |
| d/conc_t0/chat/0.0/1 | EVICT | 2 | 41.0 | 41.400000000000006 | -0.97 | level |
| d/conc_t0/chat/0.0/1 | P_16384 | 0 |  | 41.400000000000006 |  | unmeasured |
| d/conc_t0/chat/0.0/1 | P_3072 | 0 |  | 41.400000000000006 |  | unmeasured |
| d/conc_t0/chat/0.0/1 | P_UNSET | 0 |  | 41.400000000000006 |  | unmeasured |
| d/conc_t0/chat/0.0/2 | EVICT | 2 | 84.95 | 85.55 | -0.7 | level |
| d/conc_t0/chat/0.0/2 | P_16384 | 0 |  | 85.55 |  | unmeasured |
| d/conc_t0/chat/0.0/2 | P_3072 | 0 |  | 85.55 |  | unmeasured |
| d/conc_t0/chat/0.0/2 | P_UNSET | 0 |  | 85.55 |  | unmeasured |
| d/conc_t0/code/0.0/1 | EVICT | 2 | 71.15 | 71.9 | -1.04 | slower |
| d/conc_t0/code/0.0/1 | P_16384 | 0 |  | 71.9 |  | unmeasured |
| d/conc_t0/code/0.0/1 | P_3072 | 0 |  | 71.9 |  | unmeasured |
| d/conc_t0/code/0.0/1 | P_UNSET | 0 |  | 71.9 |  | unmeasured |
| d/conc_t0/code/0.0/2 | EVICT | 2 | 135.05 | 136.3 | -0.92 | level |
| d/conc_t0/code/0.0/2 | P_16384 | 0 |  | 136.3 |  | unmeasured |
| d/conc_t0/code/0.0/2 | P_3072 | 0 |  | 136.3 |  | unmeasured |
| d/conc_t0/code/0.0/2 | P_UNSET | 0 |  | 136.3 |  | unmeasured |
| p/conc_t0/chat/0.0/1 | EVICT | 0 |  | 41.45 |  | unmeasured |
| p/conc_t0/chat/0.0/1 | P_16384 | 2 | 41.7 | 41.45 | 0.6 | level |
| p/conc_t0/chat/0.0/1 | P_3072 | 2 | 41.45 | 41.45 | 0.0 | level |
| p/conc_t0/chat/0.0/1 | P_UNSET | 2 | 41.099999999999994 | 41.45 | -0.84 | level |
| p/conc_t0/code/0.0/1 | EVICT | 0 |  | 72.05000000000001 |  | unmeasured |
| p/conc_t0/code/0.0/1 | P_16384 | 2 | 72.5 | 72.05000000000001 | 0.62 | level |
| p/conc_t0/code/0.0/1 | P_3072 | 2 | 71.75 | 72.05000000000001 | -0.42 | level |
| p/conc_t0/code/0.0/1 | P_UNSET | 2 | 71.5 | 72.05000000000001 | -0.76 | level |

| cell | treatment | runs | value | base_value | gap_pct | verdict |
| --- | --- | --- | --- | --- | --- | --- |

## Exactness, all arms

# Exactness, window w1

| arm | cell | equal | total | basis |
| --- | --- | --- | --- | --- |
| C1536 | drafts | 8 | 8 | token_ids |
| C1536 | turns | 7 | 7 | resumed_from_cache |
| C1536 | drafts | 8 | 8 | token_ids |
| C1536 | fresh | 7 | 7 | token_ids |
| C1536b | drafts | 8 | 8 | token_ids |
| C1536b | turns | 7 | 7 | resumed_from_cache |
| C1536b | drafts | 8 | 8 | token_ids |
| C1536b | fresh | 7 | 7 | token_ids |
| F1 | drafts | 8 | 8 | token_ids |
| F1 | turns | 7 | 7 | resumed_from_cache |
| F1 | drafts | 8 | 8 | token_ids |
| F1 | fresh | 7 | 7 | token_ids |
| F1b | drafts | 8 | 8 | token_ids |
| F1b | turns | 7 | 7 | resumed_from_cache |
| F1b | drafts | 8 | 8 | token_ids |
| F1b | fresh | 7 | 7 | token_ids |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | fresh | 7 | 7 | token_ids |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | turns | 7 | 7 | resumed_from_cache |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | fresh | 7 | 7 | token_ids |

Concurrent equals solo (temperature 1 and 0, streams against the solo stream):

| arm | prompt | temp | streams | equal | total |
| --- | --- | --- | --- | --- | --- |
| C1536 | a/code | 1.0 | 2 | 2 | 2 |
| C1536 | a/code | 1.0 | 4 | 2 | 2 |
| C1536 | a/code | 1.0 | 6 | 2 | 2 |
| C1536 | a/chat | 1.0 | 2 | 2 | 2 |
| C1536 | a/chat | 1.0 | 4 | 2 | 2 |
| C1536 | a/chat | 1.0 | 6 | 2 | 2 |
| C1536 | a/code | 0.0 | 2 | 2 | 2 |
| C1536 | a/code | 0.0 | 4 | 2 | 2 |
| C1536 | a/code | 0.0 | 6 | 2 | 2 |
| C1536 | a/chat | 0.0 | 2 | 2 | 2 |
| C1536 | a/chat | 0.0 | 4 | 2 | 2 |
| C1536 | a/chat | 0.0 | 6 | 2 | 2 |
| C1536b | a/code | 1.0 | 2 | 2 | 2 |
| C1536b | a/code | 1.0 | 4 | 2 | 2 |
| C1536b | a/code | 1.0 | 6 | 2 | 2 |
| C1536b | a/chat | 1.0 | 2 | 2 | 2 |
| C1536b | a/chat | 1.0 | 4 | 2 | 2 |
| C1536b | a/chat | 1.0 | 6 | 2 | 2 |
| C1536b | a/code | 0.0 | 2 | 2 | 2 |
| C1536b | a/code | 0.0 | 4 | 2 | 2 |
| C1536b | a/code | 0.0 | 6 | 2 | 2 |
| C1536b | a/chat | 0.0 | 2 | 2 | 2 |
| C1536b | a/chat | 0.0 | 4 | 2 | 2 |
| C1536b | a/chat | 0.0 | 6 | 2 | 2 |
| F1 | a/code | 1.0 | 2 | 2 | 2 |
| F1 | a/code | 1.0 | 4 | 2 | 2 |
| F1 | a/code | 1.0 | 6 | 2 | 2 |
| F1 | a/chat | 1.0 | 2 | 2 | 2 |
| F1 | a/chat | 1.0 | 4 | 2 | 2 |
| F1 | a/chat | 1.0 | 6 | 2 | 2 |
| F1 | a/code | 0.0 | 2 | 2 | 2 |
| F1 | a/code | 0.0 | 4 | 2 | 2 |
| F1 | a/code | 0.0 | 6 | 2 | 2 |
| F1 | a/chat | 0.0 | 2 | 2 | 2 |
| F1 | a/chat | 0.0 | 4 | 2 | 2 |
| F1 | a/chat | 0.0 | 6 | 2 | 2 |
| F1b | a/code | 1.0 | 2 | 2 | 2 |
| F1b | a/code | 1.0 | 4 | 2 | 2 |
| F1b | a/code | 1.0 | 6 | 2 | 2 |
| F1b | a/chat | 1.0 | 2 | 2 | 2 |
| F1b | a/chat | 1.0 | 4 | 2 | 2 |
| F1b | a/chat | 1.0 | 6 | 2 | 2 |
| F1b | a/code | 0.0 | 2 | 2 | 2 |
| F1b | a/code | 0.0 | 4 | 2 | 2 |
| F1b | a/code | 0.0 | 6 | 2 | 2 |
| F1b | a/chat | 0.0 | 2 | 2 | 2 |
| F1b | a/chat | 0.0 | 4 | 2 | 2 |
| F1b | a/chat | 0.0 | 6 | 2 | 2 |
| M1 | a/code | 1.0 | 2 | 2 | 2 |
| M1 | a/code | 1.0 | 4 | 2 | 2 |
| M1 | a/code | 1.0 | 6 | 2 | 2 |
| M1 | a/chat | 1.0 | 2 | 2 | 2 |
| M1 | a/chat | 1.0 | 4 | 2 | 2 |
| M1 | a/chat | 1.0 | 6 | 2 | 2 |
| M1 | a/code | 0.0 | 2 | 2 | 2 |
| M1 | a/code | 0.0 | 4 | 2 | 2 |
| M1 | a/code | 0.0 | 6 | 2 | 2 |
| M1 | a/chat | 0.0 | 2 | 2 | 2 |
| M1 | a/chat | 0.0 | 4 | 2 | 2 |
| M1 | a/chat | 0.0 | 6 | 2 | 2 |
| M2 | a/code | 1.0 | 2 | 2 | 2 |
| M2 | a/code | 1.0 | 4 | 2 | 2 |
| M2 | a/code | 1.0 | 6 | 2 | 2 |
| M2 | a/chat | 1.0 | 2 | 2 | 2 |
| M2 | a/chat | 1.0 | 4 | 2 | 2 |
| M2 | a/chat | 1.0 | 6 | 2 | 2 |
| M2 | a/code | 0.0 | 2 | 2 | 2 |
| M2 | a/code | 0.0 | 4 | 2 | 2 |
| M2 | a/code | 0.0 | 6 | 2 | 2 |
| M2 | a/chat | 0.0 | 2 | 2 | 2 |
| M2 | a/chat | 0.0 | 4 | 2 | 2 |
| M2 | a/chat | 0.0 | 6 | 2 | 2 |

# Exactness, window w2

| arm | cell | equal | total | basis |
| --- | --- | --- | --- | --- |
| C4096 | drafts | 8 | 8 | token_ids |
| C4096 | turns | 7 | 7 | resumed_from_cache |
| C4096 | drafts | 8 | 8 | token_ids |
| C4096 | fresh | 7 | 7 | token_ids |
| C4096b | drafts | 8 | 8 | token_ids |
| C4096b | turns | 7 | 7 | resumed_from_cache |
| C4096b | drafts | 8 | 8 | token_ids |
| C4096b | fresh | 7 | 7 | token_ids |
| C6144 | drafts | 8 | 8 | token_ids |
| C6144 | turns | 7 | 7 | resumed_from_cache |
| C6144 | drafts | 8 | 8 | token_ids |
| C6144 | fresh | 7 | 7 | token_ids |
| C6144b | drafts | 8 | 8 | token_ids |
| C6144b | turns | 7 | 7 | resumed_from_cache |
| C6144b | drafts | 8 | 8 | token_ids |
| C6144b | fresh | 7 | 7 | token_ids |
| DEVCK | drafts | 8 | 8 | token_ids |
| DEVCK | turns | 7 | 7 | resumed_from_cache |
| DEVCKb | drafts | 8 | 8 | token_ids |
| DEVCKb | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | turns | 7 | 7 | resumed_from_cache |
| M1 | drafts | 8 | 8 | token_ids |
| M1 | fresh | 7 | 7 | token_ids |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | turns | 7 | 7 | resumed_from_cache |
| M2 | drafts | 8 | 8 | token_ids |
| M2 | fresh | 7 | 7 | token_ids |
| PRICE | drafts | 8 | 8 | token_ids |
| PRICE | turns | 7 | 7 | resumed_from_cache |
| PRICEb | drafts | 8 | 8 | token_ids |
| PRICEb | turns | 7 | 7 | resumed_from_cache |
| RESERVE | drafts | 8 | 8 | token_ids |
| RESERVE | turns | 7 | 7 | resumed_from_cache |
| RESERVEb | drafts | 8 | 8 | token_ids |
| RESERVEb | turns | 7 | 7 | resumed_from_cache |
| S3072 | drafts | 8 | 8 | token_ids |
| S3072 | turns | 7 | 7 | resumed_from_cache |
| S3072 | drafts | 8 | 8 | token_ids |
| S3072 | fresh | 7 | 7 | token_ids |
| S3072b | drafts | 8 | 8 | token_ids |
| S3072b | turns | 7 | 7 | resumed_from_cache |
| S3072b | drafts | 8 | 8 | token_ids |
| S3072b | fresh | 7 | 7 | token_ids |

Concurrent equals solo (temperature 1 and 0, streams against the solo stream):

| arm | prompt | temp | streams | equal | total |
| --- | --- | --- | --- | --- | --- |
| C4096 | a/code | 1.0 | 2 | 2 | 2 |
| C4096 | a/code | 1.0 | 4 | 2 | 2 |
| C4096 | a/code | 1.0 | 6 | 2 | 2 |
| C4096 | a/chat | 1.0 | 2 | 2 | 2 |
| C4096 | a/chat | 1.0 | 4 | 2 | 2 |
| C4096 | a/chat | 1.0 | 6 | 2 | 2 |
| C4096 | a/code | 0.0 | 2 | 2 | 2 |
| C4096 | a/code | 0.0 | 4 | 2 | 2 |
| C4096 | a/code | 0.0 | 6 | 2 | 2 |
| C4096 | a/chat | 0.0 | 2 | 2 | 2 |
| C4096 | a/chat | 0.0 | 4 | 2 | 2 |
| C4096 | a/chat | 0.0 | 6 | 2 | 2 |
| C4096b | a/code | 1.0 | 2 | 2 | 2 |
| C4096b | a/code | 1.0 | 4 | 2 | 2 |
| C4096b | a/code | 1.0 | 6 | 2 | 2 |
| C4096b | a/chat | 1.0 | 2 | 2 | 2 |
| C4096b | a/chat | 1.0 | 4 | 2 | 2 |
| C4096b | a/chat | 1.0 | 6 | 2 | 2 |
| C4096b | a/code | 0.0 | 2 | 2 | 2 |
| C4096b | a/code | 0.0 | 4 | 2 | 2 |
| C4096b | a/code | 0.0 | 6 | 2 | 2 |
| C4096b | a/chat | 0.0 | 2 | 2 | 2 |
| C4096b | a/chat | 0.0 | 4 | 2 | 2 |
| C4096b | a/chat | 0.0 | 6 | 2 | 2 |
| C6144 | a/code | 1.0 | 2 | 2 | 2 |
| C6144 | a/code | 1.0 | 4 | 2 | 2 |
| C6144 | a/code | 1.0 | 6 | 2 | 2 |
| C6144 | a/chat | 1.0 | 2 | 2 | 2 |
| C6144 | a/chat | 1.0 | 4 | 2 | 2 |
| C6144 | a/chat | 1.0 | 6 | 2 | 2 |
| C6144 | a/code | 0.0 | 2 | 2 | 2 |
| C6144 | a/code | 0.0 | 4 | 2 | 2 |
| C6144 | a/code | 0.0 | 6 | 2 | 2 |
| C6144 | a/chat | 0.0 | 2 | 2 | 2 |
| C6144 | a/chat | 0.0 | 4 | 2 | 2 |
| C6144 | a/chat | 0.0 | 6 | 2 | 2 |
| C6144b | a/code | 1.0 | 2 | 2 | 2 |
| C6144b | a/code | 1.0 | 4 | 2 | 2 |
| C6144b | a/code | 1.0 | 6 | 2 | 2 |
| C6144b | a/chat | 1.0 | 2 | 2 | 2 |
| C6144b | a/chat | 1.0 | 4 | 2 | 2 |
| C6144b | a/chat | 1.0 | 6 | 2 | 2 |
| C6144b | a/code | 0.0 | 2 | 2 | 2 |
| C6144b | a/code | 0.0 | 4 | 2 | 2 |
| C6144b | a/code | 0.0 | 6 | 2 | 2 |
| C6144b | a/chat | 0.0 | 2 | 2 | 2 |
| C6144b | a/chat | 0.0 | 4 | 2 | 2 |
| C6144b | a/chat | 0.0 | 6 | 2 | 2 |
| DEVCK | a/code | 1.0 | 2 | 2 | 2 |
| DEVCK | a/code | 1.0 | 4 | 2 | 2 |
| DEVCK | a/code | 1.0 | 6 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 2 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 4 | 2 | 2 |
| DEVCK | a/chat | 1.0 | 6 | 2 | 2 |
| DEVCK | a/code | 0.0 | 2 | 2 | 2 |
| DEVCK | a/code | 0.0 | 4 | 2 | 2 |
| DEVCK | a/code | 0.0 | 6 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 2 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 4 | 2 | 2 |
| DEVCK | a/chat | 0.0 | 6 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 2 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 4 | 2 | 2 |
| DEVCKb | a/code | 1.0 | 6 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 2 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 4 | 2 | 2 |
| DEVCKb | a/chat | 1.0 | 6 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 2 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 4 | 2 | 2 |
| DEVCKb | a/code | 0.0 | 6 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 2 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 4 | 2 | 2 |
| DEVCKb | a/chat | 0.0 | 6 | 2 | 2 |
| M1 | a/code | 1.0 | 2 | 2 | 2 |
| M1 | a/code | 1.0 | 4 | 2 | 2 |
| M1 | a/code | 1.0 | 6 | 2 | 2 |
| M1 | a/chat | 1.0 | 2 | 2 | 2 |
| M1 | a/chat | 1.0 | 4 | 2 | 2 |
| M1 | a/chat | 1.0 | 6 | 2 | 2 |
| M1 | a/code | 0.0 | 2 | 2 | 2 |
| M1 | a/code | 0.0 | 4 | 2 | 2 |
| M1 | a/code | 0.0 | 6 | 2 | 2 |
| M1 | a/chat | 0.0 | 2 | 2 | 2 |
| M1 | a/chat | 0.0 | 4 | 2 | 2 |
| M1 | a/chat | 0.0 | 6 | 2 | 2 |
| M2 | a/code | 1.0 | 2 | 2 | 2 |
| M2 | a/code | 1.0 | 4 | 2 | 2 |
| M2 | a/code | 1.0 | 6 | 2 | 2 |
| M2 | a/chat | 1.0 | 2 | 2 | 2 |
| M2 | a/chat | 1.0 | 4 | 2 | 2 |
| M2 | a/chat | 1.0 | 6 | 2 | 2 |
| M2 | a/code | 0.0 | 2 | 2 | 2 |
| M2 | a/code | 0.0 | 4 | 2 | 2 |
| M2 | a/code | 0.0 | 6 | 2 | 2 |
| M2 | a/chat | 0.0 | 2 | 2 | 2 |
| M2 | a/chat | 0.0 | 4 | 2 | 2 |
| M2 | a/chat | 0.0 | 6 | 2 | 2 |
| PRICE | a/code | 1.0 | 2 | 2 | 2 |
| PRICE | a/code | 1.0 | 4 | 2 | 2 |
| PRICE | a/code | 1.0 | 6 | 2 | 2 |
| PRICE | a/chat | 1.0 | 2 | 2 | 2 |
| PRICE | a/chat | 1.0 | 4 | 2 | 2 |
| PRICE | a/chat | 1.0 | 6 | 2 | 2 |
| PRICE | a/code | 0.0 | 2 | 2 | 2 |
| PRICE | a/code | 0.0 | 4 | 2 | 2 |
| PRICE | a/code | 0.0 | 6 | 2 | 2 |
| PRICE | a/chat | 0.0 | 2 | 2 | 2 |
| PRICE | a/chat | 0.0 | 4 | 2 | 2 |
| PRICE | a/chat | 0.0 | 6 | 2 | 2 |
| PRICEb | a/code | 1.0 | 2 | 2 | 2 |
| PRICEb | a/code | 1.0 | 4 | 2 | 2 |
| PRICEb | a/code | 1.0 | 6 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 2 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 4 | 2 | 2 |
| PRICEb | a/chat | 1.0 | 6 | 2 | 2 |
| PRICEb | a/code | 0.0 | 2 | 2 | 2 |
| PRICEb | a/code | 0.0 | 4 | 2 | 2 |
| PRICEb | a/code | 0.0 | 6 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 2 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 4 | 2 | 2 |
| PRICEb | a/chat | 0.0 | 6 | 2 | 2 |
| RESERVE | a/code | 1.0 | 2 | 2 | 2 |
| RESERVE | a/code | 1.0 | 4 | 2 | 2 |
| RESERVE | a/code | 1.0 | 6 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 2 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 4 | 2 | 2 |
| RESERVE | a/chat | 1.0 | 6 | 2 | 2 |
| RESERVE | a/code | 0.0 | 2 | 2 | 2 |
| RESERVE | a/code | 0.0 | 4 | 2 | 2 |
| RESERVE | a/code | 0.0 | 6 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 2 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 4 | 2 | 2 |
| RESERVE | a/chat | 0.0 | 6 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 2 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 4 | 2 | 2 |
| RESERVEb | a/code | 1.0 | 6 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 2 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 4 | 2 | 2 |
| RESERVEb | a/chat | 1.0 | 6 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 2 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 4 | 2 | 2 |
| RESERVEb | a/code | 0.0 | 6 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 2 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 4 | 2 | 2 |
| RESERVEb | a/chat | 0.0 | 6 | 2 | 2 |
| S3072 | a/code | 1.0 | 2 | 2 | 2 |
| S3072 | a/code | 1.0 | 4 | 2 | 2 |
| S3072 | a/code | 1.0 | 6 | 2 | 2 |
| S3072 | a/chat | 1.0 | 2 | 2 | 2 |
| S3072 | a/chat | 1.0 | 4 | 2 | 2 |
| S3072 | a/chat | 1.0 | 6 | 2 | 2 |
| S3072 | a/code | 0.0 | 2 | 2 | 2 |
| S3072 | a/code | 0.0 | 4 | 2 | 2 |
| S3072 | a/code | 0.0 | 6 | 2 | 2 |
| S3072 | a/chat | 0.0 | 2 | 2 | 2 |
| S3072 | a/chat | 0.0 | 4 | 2 | 2 |
| S3072 | a/chat | 0.0 | 6 | 2 | 2 |
| S3072b | a/code | 1.0 | 2 | 2 | 2 |
| S3072b | a/code | 1.0 | 4 | 2 | 2 |
| S3072b | a/code | 1.0 | 6 | 2 | 2 |
| S3072b | a/chat | 1.0 | 2 | 2 | 2 |
| S3072b | a/chat | 1.0 | 4 | 2 | 2 |
| S3072b | a/chat | 1.0 | 6 | 2 | 2 |
| S3072b | a/code | 0.0 | 2 | 2 | 2 |
| S3072b | a/code | 0.0 | 4 | 2 | 2 |
| S3072b | a/code | 0.0 | 6 | 2 | 2 |
| S3072b | a/chat | 0.0 | 2 | 2 | 2 |
| S3072b | a/chat | 0.0 | 4 | 2 | 2 |
| S3072b | a/chat | 0.0 | 6 | 2 | 2 |

# Exactness, window w3

| arm | cell | equal | total | basis |
| --- | --- | --- | --- | --- |
| M1 | drafts | 8 | 8 | token_ids |
| M2 | drafts | 8 | 8 | token_ids |
| P_16384 | drafts | 8 | 8 | token_ids |
| P_16384b | drafts | 8 | 8 | token_ids |
| P_3072 | drafts | 8 | 8 | token_ids |
| P_3072b | drafts | 8 | 8 | token_ids |
| P_UNSET | drafts | 8 | 8 | token_ids |
| P_UNSETb | drafts | 8 | 8 | token_ids |

Concurrent equals solo (temperature 1 and 0, streams against the solo stream):

| arm | prompt | temp | streams | equal | total |
| --- | --- | --- | --- | --- | --- |


## Golden coverage, checked rather than assumed

| arm | pass | streams | evidence rows | prompts in file |
| --- | --- | --- | --- | --- |
| C1536 | a | 6 | 6 | 6 |
| C1536b | a | 6 | 6 | 6 |
| F1 | a | 6 | 6 | 6 |
| F1b | a | 6 | 6 | 6 |
| M1 | a | 6 | 6 | 6 |
| M2 | a | 6 | 6 | 6 |

`bench_concurrent --prompts` sends request i item i mod the list, so the six-stream cell is the one that must carry six evidence rows for the six golden prompts. Where a row above shows fewer, golden is not claimed for that arm.

