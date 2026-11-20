# Decode cells, window w2, image tensorfold-qwen38:knob-m-1ece6e6d

Counts per treatment over the decode and TTFT cells (faster / slower / level / unmeasured):

- C4096: 3 faster, 0 slower, 13 level, 0 unmeasured, of 16
- C6144: 6 faster, 0 slower, 10 level, 0 unmeasured, of 16
- DEVCK: 0 faster, 0 slower, 12 level, 4 unmeasured, of 16
- PRICE: 0 faster, 0 slower, 12 level, 4 unmeasured, of 16
- RESERVE: 0 faster, 0 slower, 12 level, 4 unmeasured, of 16
- S3072: 0 faster, 0 slower, 16 level, 0 unmeasured, of 16

Cell, treatment, runs, treatment tok/s, main tok/s, gap %, verdict.

| cell | treatment | runs | tok/s | main | gap | verdict | tpr |
| --- | --- | --- | --- | --- | --- | --- | --- |
| a/conc_t0/chat/0.0/1 | C4096 | 2 | 41.75 | 41.55 | 0.48 | level | 3.012 |
| a/conc_t0/chat/0.0/1 | C6144 | 2 | 42.05 | 41.55 | 1.2 | faster | 3.012 |
| a/conc_t0/chat/0.0/1 | DEVCK | 2 | 41.65 | 41.55 | 0.24 | level | 3.012 |
| a/conc_t0/chat/0.0/1 | PRICE | 2 | 41.25 | 41.55 | -0.72 | level | 3.012 |
| a/conc_t0/chat/0.0/1 | RESERVE | 2 | 41.25 | 41.55 | -0.72 | level | 3.012 |
| a/conc_t0/chat/0.0/1 | S3072 | 2 | 41.5 | 41.55 | -0.12 | level | 3.012 |
| a/conc_t0/chat/0.0/2 | C4096 | 2 | 86.5 | 86.0 | 0.58 | level | 2.51 |
| a/conc_t0/chat/0.0/2 | C6144 | 2 | 86.80000000000001 | 86.0 | 0.93 | level | 2.51 |
| a/conc_t0/chat/0.0/2 | DEVCK | 2 | 86.30000000000001 | 86.0 | 0.35 | level | 2.51 |
| a/conc_t0/chat/0.0/2 | PRICE | 2 | 85.7 | 86.0 | -0.35 | level | 2.51 |
| a/conc_t0/chat/0.0/2 | RESERVE | 2 | 85.55000000000001 | 86.0 | -0.52 | level | 2.51 |
| a/conc_t0/chat/0.0/2 | S3072 | 2 | 85.9 | 86.0 | -0.12 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | C4096 | 2 | 156.1 | 155.39999999999998 | 0.45 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | C6144 | 2 | 156.5 | 155.39999999999998 | 0.71 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | DEVCK | 2 | 155.60000000000002 | 155.39999999999998 | 0.13 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | PRICE | 2 | 154.65 | 155.39999999999998 | -0.48 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | RESERVE | 2 | 154.6 | 155.39999999999998 | -0.51 | level | 2.51 |
| a/conc_t0/chat/0.0/4 | S3072 | 2 | 155.1 | 155.39999999999998 | -0.19 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | C4096 | 2 | 210.39999999999998 | 209.35000000000002 | 0.5 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | C6144 | 2 | 210.85 | 209.35000000000002 | 0.72 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | DEVCK | 2 | 209.55 | 209.35000000000002 | 0.1 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | PRICE | 2 | 208.75 | 209.35000000000002 | -0.29 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | RESERVE | 2 | 208.65 | 209.35000000000002 | -0.33 | level | 2.51 |
| a/conc_t0/chat/0.0/6 | S3072 | 2 | 208.85000000000002 | 209.35000000000002 | -0.24 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | C4096 | 2 | 257.29999999999995 | 256.6 | 0.27 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | C6144 | 2 | 257.9 | 256.6 | 0.51 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | DEVCK | 2 | 257.20000000000005 | 256.6 | 0.23 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | PRICE | 2 | 255.4 | 256.6 | -0.47 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | RESERVE | 2 | 254.89999999999998 | 256.6 | -0.66 | level | 2.51 |
| a/conc_t0/chat/0.0/8 | S3072 | 2 | 255.8 | 256.6 | -0.31 | level | 2.51 |
| a/conc_t0/code/0.0/1 | C4096 | 2 | 72.85 | 72.5 | 0.48 | level | 5.689 |
| a/conc_t0/code/0.0/1 | C6144 | 2 | 73.44999999999999 | 72.5 | 1.31 | faster | 5.689 |
| a/conc_t0/code/0.0/1 | DEVCK | 2 | 72.44999999999999 | 72.5 | -0.07 | level | 5.689 |
| a/conc_t0/code/0.0/1 | PRICE | 2 | 72.1 | 72.5 | -0.55 | level | 5.689 |
| a/conc_t0/code/0.0/1 | RESERVE | 2 | 72.35 | 72.5 | -0.21 | level | 5.689 |
| a/conc_t0/code/0.0/1 | S3072 | 2 | 72.25 | 72.5 | -0.34 | level | 5.689 |
| a/conc_t0/code/0.0/2 | C4096 | 2 | 137.95 | 137.35000000000002 | 0.44 | level | 4.83 |
| a/conc_t0/code/0.0/2 | C6144 | 2 | 138.7 | 137.35000000000002 | 0.98 | level | 4.83 |
| a/conc_t0/code/0.0/2 | DEVCK | 2 | 137.7 | 137.35000000000002 | 0.25 | level | 4.83 |
| a/conc_t0/code/0.0/2 | PRICE | 2 | 136.35000000000002 | 137.35000000000002 | -0.73 | level | 4.83 |
| a/conc_t0/code/0.0/2 | RESERVE | 2 | 136.95 | 137.35000000000002 | -0.29 | level | 4.83 |
| a/conc_t0/code/0.0/2 | S3072 | 2 | 137.0 | 137.35000000000002 | -0.25 | level | 4.83 |
| a/conc_t0/code/0.0/4 | C4096 | 2 | 242.8 | 241.9 | 0.37 | level | 4.83 |
| a/conc_t0/code/0.0/4 | C6144 | 2 | 243.9 | 241.9 | 0.83 | level | 4.83 |
| a/conc_t0/code/0.0/4 | DEVCK | 2 | 241.9 | 241.9 | 0.0 | level | 4.83 |
| a/conc_t0/code/0.0/4 | PRICE | 2 | 240.39999999999998 | 241.9 | -0.62 | level | 4.83 |
| a/conc_t0/code/0.0/4 | RESERVE | 2 | 241.25 | 241.9 | -0.27 | level | 4.83 |
| a/conc_t0/code/0.0/4 | S3072 | 2 | 240.60000000000002 | 241.9 | -0.54 | level | 4.83 |
| a/conc_t0/code/0.0/6 | C4096 | 2 | 307.20000000000005 | 305.75 | 0.47 | level | 4.491 |
| a/conc_t0/code/0.0/6 | C6144 | 2 | 308.75 | 305.75 | 0.98 | level | 4.491 |
| a/conc_t0/code/0.0/6 | DEVCK | 2 | 307.1 | 305.75 | 0.44 | level | 4.491 |
| a/conc_t0/code/0.0/6 | PRICE | 2 | 305.20000000000005 | 305.75 | -0.18 | level | 4.491 |
| a/conc_t0/code/0.0/6 | RESERVE | 2 | 305.0 | 305.75 | -0.25 | level | 4.491 |
| a/conc_t0/code/0.0/6 | S3072 | 2 | 305.2 | 305.75 | -0.18 | level | 4.491 |
| a/conc_t0/code/0.0/8 | C4096 | 2 | 371.75 | 370.0 | 0.47 | level | 4.491 |
| a/conc_t0/code/0.0/8 | C6144 | 2 | 372.75 | 370.0 | 0.74 | level | 4.491 |
| a/conc_t0/code/0.0/8 | DEVCK | 2 | 371.05 | 370.0 | 0.28 | level | 4.491 |
| a/conc_t0/code/0.0/8 | PRICE | 2 | 368.4 | 370.0 | -0.43 | level | 4.491 |
| a/conc_t0/code/0.0/8 | RESERVE | 2 | 368.0 | 370.0 | -0.54 | level | 4.491 |
| a/conc_t0/code/0.0/8 | S3072 | 2 | 368.95 | 370.0 | -0.28 | level | 4.491 |
| a/openai_t0/fibonacci-raw/0.0/1 | C4096 | 2 | 72.9251791626966 | 72.62398571738491 | 0.41 | level | 5.689 |
| a/openai_t0/fibonacci-raw/0.0/1 | C6144 | 2 | 73.48545026817155 | 72.62398571738491 | 1.19 | faster | 5.689 |
| a/openai_t0/fibonacci-raw/0.0/1 | DEVCK | 2 | 72.76208135884309 | 72.62398571738491 | 0.19 | level | 5.689 |
| a/openai_t0/fibonacci-raw/0.0/1 | PRICE | 2 | 72.11297243954809 | 72.62398571738491 | -0.7 | level | 5.689 |
| a/openai_t0/fibonacci-raw/0.0/1 | RESERVE | 2 | 72.3895397549094 | 72.62398571738491 | -0.32 | level | 5.689 |
| a/openai_t0/fibonacci-raw/0.0/1 | S3072 | 2 | 72.7761137365143 | 72.62398571738491 | 0.21 | level | 5.689 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | C4096 | 2 | 41.935749771306405 | 41.67959264964674 | 0.61 | level | 3.012 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | C6144 | 2 | 42.117841839674256 | 41.67959264964674 | 1.05 | level | 3.012 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | DEVCK | 2 | 41.69946056703398 | 41.67959264964674 | 0.05 | level | 3.012 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | PRICE | 2 | 41.42406496215591 | 41.67959264964674 | -0.61 | level | 3.012 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | RESERVE | 2 | 41.56452228521343 | 41.67959264964674 | -0.28 | level | 3.012 |
| a/openai_t0/gpu-chat-no-think/0.0/1 | S3072 | 2 | 41.7069343607902 | 41.67959264964674 | 0.07 | level | 3.012 |
