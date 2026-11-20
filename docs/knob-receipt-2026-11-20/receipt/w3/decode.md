# Decode cells, window w3, image tensorfold-qwen38:knob-m-1ece6e6d

Counts per treatment over the decode and TTFT cells (faster / slower / level / unmeasured):

- EVICT: 0 faster, 1 slower, 3 level, 6 unmeasured, of 10
- P_16384: 2 faster, 0 slower, 4 level, 4 unmeasured, of 10
- P_3072: 0 faster, 3 slower, 3 level, 4 unmeasured, of 10
- P_UNSET: 0 faster, 2 slower, 4 level, 4 unmeasured, of 10

Cell, treatment, runs, treatment tok/s, main tok/s, gap %, verdict.

| cell | treatment | runs | tok/s | main | gap | verdict | tpr |
| --- | --- | --- | --- | --- | --- | --- | --- |
| d/conc_t0/chat/0.0/1 | EVICT | 2 | 41.0 | 41.400000000000006 | -0.97 | level | 3.012 |
| d/conc_t0/chat/0.0/1 | P_16384 | 0 | None | 41.400000000000006 | None | unmeasured | None |
| d/conc_t0/chat/0.0/1 | P_3072 | 0 | None | 41.400000000000006 | None | unmeasured | None |
| d/conc_t0/chat/0.0/1 | P_UNSET | 0 | None | 41.400000000000006 | None | unmeasured | None |
| d/conc_t0/chat/0.0/2 | EVICT | 2 | 84.95 | 85.55 | -0.7 | level | 2.51 |
| d/conc_t0/chat/0.0/2 | P_16384 | 0 | None | 85.55 | None | unmeasured | None |
| d/conc_t0/chat/0.0/2 | P_3072 | 0 | None | 85.55 | None | unmeasured | None |
| d/conc_t0/chat/0.0/2 | P_UNSET | 0 | None | 85.55 | None | unmeasured | None |
| d/conc_t0/code/0.0/1 | EVICT | 2 | 71.15 | 71.9 | -1.04 | slower | 5.689 |
| d/conc_t0/code/0.0/1 | P_16384 | 0 | None | 71.9 | None | unmeasured | None |
| d/conc_t0/code/0.0/1 | P_3072 | 0 | None | 71.9 | None | unmeasured | None |
| d/conc_t0/code/0.0/1 | P_UNSET | 0 | None | 71.9 | None | unmeasured | None |
| d/conc_t0/code/0.0/2 | EVICT | 2 | 135.05 | 136.3 | -0.92 | level | 4.83 |
| d/conc_t0/code/0.0/2 | P_16384 | 0 | None | 136.3 | None | unmeasured | None |
| d/conc_t0/code/0.0/2 | P_3072 | 0 | None | 136.3 | None | unmeasured | None |
| d/conc_t0/code/0.0/2 | P_UNSET | 0 | None | 136.3 | None | unmeasured | None |
| p/conc_t0/chat/0.0/1 | EVICT | 0 | None | 41.45 | None | unmeasured | None |
| p/conc_t0/chat/0.0/1 | P_16384 | 2 | 41.7 | 41.45 | 0.6 | level | 3.012 |
| p/conc_t0/chat/0.0/1 | P_3072 | 2 | 41.45 | 41.45 | 0.0 | level | 3.012 |
| p/conc_t0/chat/0.0/1 | P_UNSET | 2 | 41.099999999999994 | 41.45 | -0.84 | level | 3.012 |
| p/conc_t0/code/0.0/1 | EVICT | 0 | None | 72.05000000000001 | None | unmeasured | None |
| p/conc_t0/code/0.0/1 | P_16384 | 2 | 72.5 | 72.05000000000001 | 0.62 | level | 5.689 |
| p/conc_t0/code/0.0/1 | P_3072 | 2 | 71.75 | 72.05000000000001 | -0.42 | level | 5.689 |
| p/conc_t0/code/0.0/1 | P_UNSET | 2 | 71.5 | 72.05000000000001 | -0.76 | level | 5.689 |
