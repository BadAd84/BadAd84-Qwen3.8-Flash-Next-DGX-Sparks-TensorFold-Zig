Decode with the drafter on, bench_concurrent aggregate tok/s (median of 3 reps):

| temperature | prompt | streams | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|---|---|
| 1 | code | 1 | 69.9 | 68.8 | 71.2 | 68.7 | 1.7% | -0.7% | +2.7% |
| 1 | code | 2 | 87.8 | 86.2 | 88.0 | 86.3 | 1.7% | -1.0% below both | +1.1% |
| 1 | code | 4 | 127.0 | 125.1 | 127.9 | 124.8 | 1.7% | -0.6% | +1.6% |
| 1 | chat | 1 | 44.4 | 43.7 | 43.5 | 44.1 | 0.7% | -1.2% below both | -1.7% below both |
| 1 | chat | 2 | 69.1 | 68.2 | 68.0 | 68.9 | 0.3% | -1.2% below both | -1.4% below both |
| 1 | chat | 4 | 102.6 | 101.7 | 102.3 | 102.3 | 0.3% | -0.7% below both | -0.1% |
| 0 | code | 1 | 71.3 | 72.2 | 73.7 | 71.4 | 0.1% | +1.2% | +3.3% |
| 0 | code | 2 | 135.3 | 137.0 | 141.5 | 135.8 | 0.4% | +1.1% | +4.4% |
| 0 | code | 4 | 236.6 | 240.1 | 246.8 | 237.2 | 0.3% | +1.4% | +4.2% |
| 0 | chat | 1 | 45.8 | 46.5 | 46.3 | 45.8 | 0.0% | +1.5% | +1.1% |
| 0 | chat | 2 | 84.8 | 85.8 | 87.9 | 85.2 | 0.5% | +0.9% | +3.4% |
| 0 | chat | 4 | 152.6 | 154.2 | 156.1 | 152.6 | 0.0% | +1.0% | +2.3% |

Decode with "draft": false on every request (bench_nodraft.py, the same client), aggregate tok/s:

| temperature | prompt | streams | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|---|---|
| 1 | code | 1 | 26.8 | 26.8 | 26.7 | 26.7 | 0.4% | +0.2% | -0.2% |
| 1 | code | 2 | 45.6 | 45.5 | 45.5 | 45.5 | 0.2% | -0.1% | -0.1% |
| 1 | code | 4 | 72.2 | 72.2 | 72.1 | 71.8 | 0.6% | +0.3% | +0.1% |
| 1 | chat | 1 | 26.9 | 26.7 | 26.8 | 26.8 | 0.4% | -0.6% below both | -0.2% |
| 1 | chat | 2 | 45.4 | 45.2 | 45.3 | 45.2 | 0.4% | -0.2% | +0.0% |
| 1 | chat | 4 | 70.9 | 71.2 | 70.9 | 71.2 | 0.4% | +0.2% | -0.2% |
| 0 | code | 1 | 27.0 | 26.9 | 26.9 | 27.0 | 0.0% | -0.4% below both | -0.4% below both |
| 0 | code | 2 | 50.8 | 50.7 | 50.7 | 51.0 | 0.4% | -0.4% below both | -0.4% below both |
| 0 | code | 4 | 90.6 | 91.0 | 90.9 | 91.9 | 1.4% | -0.3% | -0.4% |
| 0 | chat | 1 | 26.6 | 26.8 | 26.9 | 26.7 | 0.4% | +0.6% | +0.9% |
| 0 | chat | 2 | 50.3 | 50.7 | 50.8 | 50.3 | 0.0% | +0.8% | +1.0% |
| 0 | chat | 4 | 91.0 | 91.3 | 91.6 | 90.7 | 0.3% | +0.5% | +0.8% |

One stream at temperature 1.0, bench_openai decode_tps (median of 3 seeds):

| prompt | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|
| fibonacci-raw | 65.8 | 64.7 | 67.9 | 64.2 | 2.5% | -0.5% | +4.5% |
| gpu-chat-no-think | 45.8 | 44.8 | 47.6 | 44.6 | 2.5% | -0.9% | +5.3% |

Drafter on against "draft": false in the same boot, aggregate tok/s (on / off = ratio):

| temperature | prompt | streams | main: on / off | PR, unset: on / off | PR, mxfp8: on / off | main again: on / off |
|---|---|---|---|---|---|---|
| 1 | code | 1 | 69.9 / 26.8 = 2.61x | 68.8 / 26.8 = 2.57x | 71.2 / 26.7 = 2.67x | 68.7 / 26.7 = 2.57x |
| 1 | code | 2 | 87.8 / 45.6 = 1.93x | 86.2 / 45.5 = 1.89x | 88.0 / 45.5 = 1.93x | 86.3 / 45.5 = 1.90x |
| 1 | code | 4 | 127.0 / 72.2 = 1.76x | 125.1 / 72.2 = 1.73x | 127.9 / 72.1 = 1.77x | 124.8 / 71.8 = 1.74x |
| 1 | chat | 1 | 44.4 / 26.9 = 1.65x | 43.7 / 26.7 = 1.64x | 43.5 / 26.8 = 1.62x | 44.1 / 26.8 = 1.65x |
| 1 | chat | 2 | 69.1 / 45.4 = 1.52x | 68.2 / 45.2 = 1.51x | 68.0 / 45.3 = 1.50x | 68.9 / 45.2 = 1.52x |
| 1 | chat | 4 | 102.6 / 70.9 = 1.45x | 101.7 / 71.2 = 1.43x | 102.3 / 70.9 = 1.44x | 102.3 / 71.2 = 1.44x |
| 0 | code | 1 | 71.3 / 27.0 = 2.64x | 72.2 / 26.9 = 2.68x | 73.7 / 26.9 = 2.74x | 71.4 / 27.0 = 2.64x |
| 0 | code | 2 | 135.3 / 50.8 = 2.66x | 137.0 / 50.7 = 2.70x | 141.5 / 50.7 = 2.79x | 135.8 / 51.0 = 2.66x |
| 0 | code | 4 | 236.6 / 90.6 = 2.61x | 240.1 / 91.0 = 2.64x | 246.8 / 90.9 = 2.72x | 237.2 / 91.9 = 2.58x |
| 0 | chat | 1 | 45.8 / 26.6 = 1.72x | 46.5 / 26.8 = 1.74x | 46.3 / 26.9 = 1.72x | 45.8 / 26.7 = 1.72x |
| 0 | chat | 2 | 84.8 / 50.3 = 1.69x | 85.8 / 50.7 = 1.69x | 87.9 / 50.8 = 1.73x | 85.2 / 50.3 = 1.69x |
| 0 | chat | 4 | 152.6 / 91.0 = 1.68x | 154.2 / 91.3 = 1.69x | 156.1 / 91.6 = 1.70x | 152.6 / 90.7 = 1.68x |

Checks (bench_concurrent's own token_sha256 comparisons; served_exactness.py drafts at 64 tokens):

| arm | run | concurrent == alone | alone == serial | failed | unmeasured | tokens a chunk (pooled) |
|---|---|---|---|---|---|---|
| main | on_t1 | 42/42 | 8/8 | 0 | 0 | 2.39-4.57 |
| main | off_t1 | 42/42 | 8/8 | 0 | 0 | 1.00-1.00 |
| main | off_t0 | 42/42 | 2/2 | 0 | 0 | 1.00-1.00 |
| main | on_t0 | 42/42 | 2/2 | 0 | 0 | 2.51-5.22 |
| PR, unset | on_t1 | 42/42 | 8/8 | 0 | 0 | 2.39-4.57 |
| PR, unset | off_t1 | 42/42 | 8/8 | 0 | 0 | 1.00-1.00 |
| PR, unset | off_t0 | 42/42 | 2/2 | 0 | 0 | 1.00-1.00 |
| PR, unset | on_t0 | 42/42 | 2/2 | 0 | 0 | 2.51-5.22 |
| PR, mxfp8 | on_t1 | 42/42 | 8/8 | 0 | 0 | 2.31-4.41 |
| PR, mxfp8 | off_t1 | 42/42 | 8/8 | 0 | 0 | 1.00-1.00 |
| PR, mxfp8 | off_t0 | 42/42 | 2/2 | 0 | 0 | 1.00-1.00 |
| PR, mxfp8 | on_t0 | 42/42 | 2/2 | 0 | 0 | 2.54-5.22 |
| main again | on_t1 | 42/42 | 8/8 | 0 | 0 | 2.39-4.57 |
| main again | off_t1 | 42/42 | 8/8 | 0 | 0 | 1.00-1.00 |
| main again | off_t0 | 42/42 | 2/2 | 0 | 0 | 1.00-1.00 |
| main again | on_t0 | 42/42 | 2/2 | 0 | 0 | 2.51-5.22 |

| arm | drafted == "draft": false | drafted count of the "draft": false replies | accepted a drafted reply |
|---|---|---|---|
| main | 8/8 | 0 | 5-54 |
| PR, unset | 8/8 | 0 | 5-54 |
| PR, mxfp8 | 8/8 | 0 | 5-54 |
| main again | 8/8 | 0 | 5-54 |

PR cells below both main arms: 11
- drafter on, temperature 1, code, 2 streams: PR, unset 86.2 against main 87.8 and 86.3
- drafter on, temperature 1, chat, 1 streams: PR, unset 43.7 against main 44.4 and 44.1
- drafter on, temperature 1, chat, 1 streams: PR, mxfp8 43.5 against main 44.4 and 44.1
- drafter on, temperature 1, chat, 2 streams: PR, unset 68.2 against main 69.1 and 68.9
- drafter on, temperature 1, chat, 2 streams: PR, mxfp8 68.0 against main 69.1 and 68.9
- drafter on, temperature 1, chat, 4 streams: PR, unset 101.7 against main 102.6 and 102.3
- drafter off, temperature 1, chat, 1 streams: PR, unset 26.7 against main 26.9 and 26.8
- drafter off, temperature 0, code, 1 streams: PR, unset 26.9 against main 27.0 and 27.0
- drafter off, temperature 0, code, 1 streams: PR, mxfp8 26.9 against main 27.0 and 27.0
- drafter off, temperature 0, code, 2 streams: PR, unset 50.7 against main 50.8 and 51.0
- drafter off, temperature 0, code, 2 streams: PR, mxfp8 50.7 against main 50.8 and 51.0

Drafter-on cells slower than "draft": false: 0
