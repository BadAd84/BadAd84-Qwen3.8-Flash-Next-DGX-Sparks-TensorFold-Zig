Boots: main: sampled0014/main, sampled0014/main-again, sampled0014b/main-1, sampled0014b/main-2; PR, unset: sampled0014/pr-default, sampled0014b/pr-default-1, sampled0014b/pr-default-2; PR, mxfp8: sampled0014/pr-mxfp8, sampled0014b/pr-mxfp8-1, sampled0014b/pr-mxfp8-2

Sampled decode (temperature 1.0), drafter on, bench_concurrent aggregate tok/s (each boot's median of 3 reps):

| prompt | streams | main: mean (boots) | PR, unset: mean (boots) | PR, mxfp8: mean (boots) | main range | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|
| code | 1 | 69.2 (69.9, 68.7, 68.6, 69.7) | 69.0 (68.8, 68.7, 69.5) | 70.6 (71.2, 70.1, 70.4) | 1.9% | -0.3% | +1.9% |
| code | 2 | 86.9 (87.8, 86.3, 86.3, 87.3) | 86.6 (86.2, 86.4, 87.2) | 87.2 (88.0, 86.8, 86.9) | 1.7% | -0.4% | +0.4% |
| code | 4 | 125.7 (127.0, 124.8, 124.9, 126.2) | 125.3 (125.1, 124.8, 125.9) | 126.9 (127.9, 126.3, 126.5) | 1.7% | -0.4% | +0.9% |
| chat | 1 | 44.0 (44.4, 44.1, 43.5, 44.2) | 43.8 (43.7, 43.7, 44.1) | 43.2 (43.5, 42.7, 43.3) | 2.0% | -0.5% | -2.0% below every main boot |
| chat | 2 | 68.5 (69.1, 68.9, 68.0, 68.2) | 68.4 (68.2, 68.1, 68.8) | 67.7 (68.0, 67.2, 68.0) | 1.6% | -0.3% | -1.2% below every main boot |
| chat | 4 | 101.7 (102.6, 102.3, 100.8, 101.0) | 101.6 (101.7, 101.1, 102.0) | 101.8 (102.3, 101.1, 102.1) | 1.8% | -0.1% | +0.2% |

One stream at temperature 1.0, bench_openai decode tok/s by seed, each arm's mean over its boots (boot count in brackets):

| prompt | seed | main (boots) | PR, unset (boots) | PR, mxfp8 (boots) | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|
| fibonacci-raw | 1234 | 69.3 (4) | 69.3 (3) | 70.9 (3) | -0.1% | +2.3% |
| fibonacci-raw | 1235 | 58.2 (4) | 58.2 (3) | 58.8 (3) | -0.0% | +1.0% |
| fibonacci-raw | 1236 | 64.9 (4) | 64.7 (3) | 67.0 (3) | -0.2% | +3.3% |
| fibonacci-raw | 1237 | 63.6 (2) | 63.6 (2) | 65.9 (2) | -0.0% | +3.7% |
| fibonacci-raw | 1238 | 61.9 (2) | 62.6 (2) | 62.0 (2) | +1.2% | +0.2% |
| fibonacci-raw | 1239 | 53.7 (2) | 54.7 (2) | 57.5 (2) | +1.8% | +7.0% |
| fibonacci-raw | 1240 | 63.0 (2) | 64.0 (2) | 64.8 (2) | +1.5% | +2.8% |
| fibonacci-raw | 1241 | 60.5 (2) | 61.3 (2) | 61.2 (2) | +1.3% | +1.2% |
| fibonacci-raw | 1242 | 67.7 (2) | 68.4 (2) | 67.2 (2) | +1.0% | -0.7% |
| fibonacci-raw | mean of 9 seeds | 62.5 | 63.0 | 63.9 | +0.7% (5/9 seeds faster) | +2.2% (8/9 seeds faster) |
| gpu-chat-no-think | 1234 | 43.9 (4) | 43.8 (3) | 43.0 (3) | -0.2% | -2.1% |
| gpu-chat-no-think | 1235 | 48.1 (4) | 47.8 (3) | 48.7 (3) | -0.6% | +1.3% |
| gpu-chat-no-think | 1236 | 45.1 (4) | 44.9 (3) | 47.0 (3) | -0.5% | +4.1% |
| gpu-chat-no-think | 1237 | 46.5 (2) | 46.4 (2) | 46.9 (2) | -0.1% | +0.9% |
| gpu-chat-no-think | 1238 | 42.8 (2) | 44.1 (2) | 42.8 (2) | +3.1% | -0.1% |
| gpu-chat-no-think | 1239 | 45.6 (2) | 46.8 (2) | 47.4 (2) | +2.6% | +3.9% |
| gpu-chat-no-think | 1240 | 42.5 (2) | 43.4 (2) | 44.2 (2) | +2.2% | +4.0% |
| gpu-chat-no-think | 1241 | 44.2 (2) | 45.3 (2) | 46.1 (2) | +2.4% | +4.3% |
| gpu-chat-no-think | 1242 | 44.7 (2) | 45.8 (2) | 45.3 (2) | +2.4% | +1.3% |
| gpu-chat-no-think | mean of 9 seeds | 44.8 | 45.4 | 45.7 | +1.2% (5/9 seeds faster) | +1.9% (7/9 seeds faster) |

PR arm means below every main boot: 2
- chat, 1 streams: PR, mxfp8 mean 43.2 against main boots 43.5-44.4
- chat, 2 streams: PR, mxfp8 mean 67.7 against main boots 68.0-69.1
