# Parity window: r5dev40 against production (spark6)

Arms: **P** production (`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`) and **D** `tensorfold-qwen38:r5dev40`,
one fresh boot a level each, interleaved; decode = `tfm_decode_ids.py` (the target's own harness + token
hashes), 512 greedy tokens, 3 passes; TTFT = the target's `ttft.py`, 2 reps, idle.

## Declared repeats and the rerun rule, as executed

Repeats: decode 3 passes a cell (median reported), TTFT 2 reps a case (median), warm 2 reps and both must
report cached tokens. Rule R1-R5 is in window.sh's header; score_cells.py applied it after the first pass:

```
score1.txt:
RERUN D c1 R1 prose spread 27.5%
RERUN D c2 R1 prose spread 14.6%; R1 code spread 10.8%; R4 cold1k-on spread 14.3%
RERUN D c4 R1 prose spread 7.9%; R4 cold1k-off spread 43.0%; R4 warm2k spread 16.2%
RERUN D c6 R4 cold1k-off spread 48.1%
RERUN D c8 R4 cold1k-off spread 26.3%; R4 cold1k-on spread 15.9%
RERUN P c1 R1 prose spread 23.8%; R1 code spread 13.7%; R4 cold1k-on spread 10.5%
RERUN P c2 R1 prose spread 16.5%; R1 code spread 10.6%; R4 cold1k-off spread 33.6%
RERUN P c6 R1 code spread 8.0%; R4 warm2k spread 13.3%
RERUN P c8 R1 code spread 5.5%
SCORE-SUMMARY cells 10 rerun 9
```
```
rerun1.levels:
1
2
4
6
8
```
```
score2.txt:
RERUN D c1 R1 prose spread 28.9%
RERUN D c2 R1 prose spread 13.7%; R1 code spread 8.5%; R4 cold1k-off spread 25.4%; R4 warm2k spread 14.7%
RERUN D c4 R1 prose spread 5.6%; R4 cold1k-off spread 45.7%
RERUN D c6 R1 code spread 5.1%; R4 cold1k-off spread 50.6%
RERUN D c8 R1 prose spread 5.6%; R4 cold1k-off spread 54.7%; R4 cold1k-on spread 11.8%
RERUN P c1 R1 prose spread 23.2%; R1 code spread 13.8%
RERUN P c2 R1 prose spread 17.6%; R1 code spread 10.6%
RERUN P c4 R4 cold1k-off spread 21.1%
RERUN P c6 R1 code spread 6.9%
RERUN P c8 R1 code spread 6.7%
SCORE-SUMMARY cells 10 rerun 10 final
```

## Preflight

- live production before the window: `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`
- image P: `['tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7']` id `sha256:235211ea77ee4e` labels kernels=present
- image D: `['tensorfold-qwen38:r5dev40']` id `sha256:adc40fe3ea7b58` labels kernels=embedded
- env names P: ENVSTR names 54 carried 53 missing 1
- launch flags P: FLAG-FULL ACCEPTED 28 tokens :: tensorfold: /nonexistent/argument-check is neither a directory nor a Hugging Face repo id (owner/name)
- launch flags P: FLAG-SUMMARY accepted 15 known-other 3 rejected 0 other 0
- env names D: ENVSTR names 114 carried 101 missing 13
- launch flags D: FLAG-FULL ACCEPTED 31 tokens :: tensorfold: /nonexistent/argument-check is neither a directory nor a Hugging Face repo id (owner/name)
- launch flags D: FLAG-SUMMARY accepted 16 known-other 0 rejected 0 other 0
- model directory P: `/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd`
- model directory D: `/root/.cache/huggingface/hub/models--azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd`
- launch flag names, dry run against the live production command: SAME 15 flag names as the live production command

## Decode, aggregate tok/s (per-stream median in brackets), median of 3 passes

| concurrency | P prose | D prose | D/P | P code | D code | D/P |
|---:|---|---|---:|---|---|---:|
| 1 | 71.8 (71.8) | 65.6 (65.6) | 0.914 | 115.4 (115.4) | 113.5 (113.5) | 0.984 |
| 2 | 105.6 (52.8) | 100.0 (50.0) | 0.947 | 176.1 (88.0) | 169.5 (84.8) | 0.963 |
| 4 | 165.2 (41.7) | 155.8 (40.0) | 0.943 | 258.1 (64.5) | 239.5 (61.4) | 0.928 |
| 6 | 206.6 (35.8) | 185.9 (31.2) | 0.900 | 314.2 (53.1) | 282.8 (47.4) | 0.900 |
| 8 | 239.2 (30.4) | 214.0 (27.0) | 0.895 | 380.8 (47.8) | 326.7 (40.8) | 0.858 |

## Decode, tokens per wall second

| concurrency | P prose | D prose | D/P | P code | D code | D/P |
|---:|---|---|---:|---|---|---:|
| 1 | 71.1 | 64.8 | 0.911 | 113.7 | 111.5 | 0.981 |
| 2 | 101.5 | 96.2 | 0.948 | 171.8 | 158.0 | 0.920 |
| 4 | 153.6 | 146.7 | 0.955 | 231.5 | 212.5 | 0.918 |
| 6 | 190.4 | 170.8 | 0.897 | 285.1 | 260.4 | 0.913 |
| 8 | 216.3 | 194.1 | 0.897 | 337.5 | 292.8 | 0.868 |

## Both arms against the recorded target (docs/SPEED-TARGET-1.2.6.md, 2026-11-10)

| concurrency | P prose / doc | D prose / doc | P code / doc | D code / doc |
|---:|---|---|---|---|
| 1 | 1.013 | 0.925 | 1.021 | 1.004 |
| 2 | 1.022 | 0.968 | 1.014 | 0.976 |
| 4 | 1.018 | 0.960 | 1.016 | 0.943 |
| 6 | 1.022 | 0.919 | 1.008 | 0.907 |
| 8 | 1.009 | 0.903 | 1.028 | 0.882 |

P against the doc over the ten aggregate cells: geometric mean **1.017** (min 1.008, max 1.028)

D against the doc over the ten aggregate cells: geometric mean **0.938** (min 0.882, max 1.004)

D against P over the ten aggregate cells: geometric mean **0.922**

## Cold TTFT, s (median of 2 reps, idle; 1k is the harness control cell)

| case | 1 | 2 | 4 | 6 | 8 |
|---|---|---|---|---|---|
| cold8k-off P | 2.588 | 2.590 | 2.606 | 2.571 | 2.583 |
| cold8k-off D | 2.954 | 2.954 | 2.889 | 3.033 | 3.034 |
| cold8k-off D/P | 1.141 | 1.141 | 1.109 | 1.180 | 1.175 |
| cold8k-on P | 2.625 | 2.624 | 2.644 | 2.609 | 2.605 |
| cold8k-on D | 2.928 | 2.947 | 2.974 | 3.052 | 2.993 |
| cold8k-on D/P | 1.115 | 1.123 | 1.125 | 1.170 | 1.149 |
| cold32k-off P | 10.490 | 10.531 | 10.502 | 10.537 | 10.603 |
| cold32k-off D | 11.800 | 11.858 | 11.748 | 11.875 | 11.826 |
| cold32k-off D/P | 1.125 | 1.126 | 1.119 | 1.127 | 1.115 |
| cold32k-on P | 10.546 | 10.532 | 10.517 | 10.542 | 10.552 |
| cold32k-on D | 11.736 | 11.774 | 11.793 | 11.826 | 11.764 |
| cold32k-on D/P | 1.113 | 1.118 | 1.121 | 1.122 | 1.115 |
| cold1k-off P | 0.392 | 0.398 | 0.445 | 0.386 | 0.389 |
| cold1k-off D | 0.491 | 0.518 | 0.586 | 0.599 | 0.605 |
| cold1k-off D/P | 1.253 | 1.302 | 1.317 | 1.552 | 1.555 |
| warm2k P | 1.095 | 1.079 | 1.058 | 1.159 | 1.136 |
| warm2k D | 1.145 | 1.203 | 1.190 | 1.208 | 1.153 |
| warm2k D/P | 1.046 | 1.115 | 1.125 | 1.042 | 1.015 |

Against the doc (idle column): P/doc and D/doc.

| case | 1 P/D | 2 P/D | 4 P/D | 6 P/D | 8 P/D |
|---|---|---|---|---|---|
| cold8k-off | 0.977 / 1.115 | 0.943 / 1.075 | 0.952 / 1.056 | 0.978 / 1.154 | 0.952 / 1.118 |
| cold8k-on | 0.962 / 1.073 | 0.900 / 1.011 | 0.912 / 1.026 | 0.932 / 1.091 | 0.972 / 1.117 |
| cold32k-off | 0.974 / 1.096 | 0.958 / 1.079 | 0.964 / 1.079 | 0.973 / 1.096 | 0.979 / 1.092 |
| cold32k-on | 0.984 / 1.095 | 0.976 / 1.091 | 0.975 / 1.093 | 0.971 / 1.089 | 0.966 / 1.077 |
| cold1k-off | 0.933 / 1.169 | 0.701 / 0.912 | 0.901 / 1.186 | 0.937 / 1.454 | 0.896 / 1.394 |

## Warm agent turn: a kept 100k conversation plus 2k new tokens, idle

| concurrency | P med s (n, cached) | D med s (n, cached) | D/P | doc |
|---:|---|---|---:|---:|
| 1 | 1.095 (n2, x0, cached 100222,100215 of prompt 102322,102304) | 1.145 (n2, x0, cached 100117,100117 of prompt 102223,102189) | 1.046 | 1.403 |
| 2 | 1.079 (n2, x0, cached 100424,100417 of prompt 102491,102504) | 1.203 (n2, x0, cached 99966,99966 of prompt 102103,102039) | 1.115 | 1.282 |
| 4 | 1.058 (n2, x0, cached 100116,100109 of prompt 102203,102186) | 1.190 (n2, x0, cached 100115,100115 of prompt 102194,102229) | 1.125 | 1.372 |
| 6 | 1.159 (n2, x0, cached 100162,100155 of prompt 102252,102230) | 1.208 (n2, x0, cached 100132,100132 of prompt 102231,102211) | 1.042 | 1.268 |
| 8 | 1.136 (n2, x0, cached 100236,100229 of prompt 102286,102282) | 1.153 (n2, x0, cached 100193,100193 of prompt 102275,102246) | 1.015 | 1.366 |

## Boot, memory and golden

| concurrency | arm | boot s | sequence memory | golden | image |
|---:|---|---:|---|---|---|
| 1 | P | 85.5 | 28.81 GiB (40.81 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer | 6/6 | `zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211e` |
| 1 | D | 151.8 | - | 6/6 | `r5dev40` `sha256:adc40fe` |
| 2 | P | 82.4 | 28.47 GiB (40.47 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer | 6/6 | `zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211e` |
| 2 | D | 148.7 | - | 6/6 | `r5dev40` `sha256:adc40fe` |
| 4 | P | 85.7 | 29.09 GiB (41.09 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer | 6/6 | `zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211e` |
| 4 | D | 151.8 | - | 6/6 | `r5dev40` `sha256:adc40fe` |
| 6 | P | 85.7 | 27.43 GiB (39.43 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer | 6/6 | `zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211e` |
| 6 | D | 149.0 | - | 6/6 | `r5dev40` `sha256:adc40fe` |
| 8 | P | 88.5 | 28.54 GiB (40.54 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer | 6/6 | `zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211e` |
| 8 | D | 148.8 | - | 6/6 | `r5dev40` `sha256:adc40fe` |
| 1 | doc | 83 | 26.43 GiB | 6/6 | - |
| 2 | doc | 87 | 25.27 GiB | 6/6 | - |
| 4 | doc | 90 | 26.07 GiB | 6/6 | - |
| 6 | doc | 90 | 25.00 GiB | 6/6 | - |
| 8 | doc | 90 | 24.14 GiB | 6/6 | - |

## Thermals and traffic (GB10: clocks sag with sustained load, so every probe window's reading is kept)

| concurrency | arm | at boot | after golden | after decode | after TTFT | foreign request lines |
|---:|---|---|---|---|---|---:|
| 1 | P | 65,2398MHz,14.60W,[N/A] | 59,2509MHz,39.08W,[N/A] | 60,2509MHz,37.84W,[N/A] | 72,2470MHz,61.17W,[N/A] | 0 |
| 1 | D | 66,2398MHz,14.45W,[N/A] | 55,2502MHz,36.07W,[N/A] | 57,2509MHz,36.65W,[N/A] | 70,2483MHz,68.63W,[N/A] | 0 |
| 2 | P | 66,2398MHz,14.77W,[N/A] | 60,2509MHz,39.73W,[N/A] | 61,2509MHz,38.61W,[N/A] | 72,2470MHz,61.78W,[N/A] | 0 |
| 2 | D | 66,2398MHz,14.59W,[N/A] | 55,2509MHz,36.97W,[N/A] | 59,2509MHz,36.42W,[N/A] | 68,2483MHz,68.50W,[N/A] | 0 |
| 4 | P | 65,2398MHz,14.38W,[N/A] | 59,2509MHz,38.93W,[N/A] | 60,2509MHz,37.95W,[N/A] | 72,2489MHz,63.44W,[N/A] | 0 |
| 4 | D | 65,2398MHz,14.24W,[N/A] | 54,2509MHz,35.99W,[N/A] | 59,2509MHz,36.38W,[N/A] | 69,2483MHz,63.59W,[N/A] | 0 |
| 6 | P | 66,2398MHz,14.60W,[N/A] | 61,2509MHz,39.19W,[N/A] | 63,2489MHz,38.87W,[N/A] | 71,2470MHz,56.13W,[N/A] | 0 |
| 6 | D | 66,1495MHz,11.08W,[N/A] | 55,2509MHz,37.12W,[N/A] | 61,2509MHz,38.11W,[N/A] | 70,2489MHz,63.43W,[N/A] | 0 |
| 8 | P | 65,2398MHz,14.51W,[N/A] | 59,2509MHz,35.84W,[N/A] | 62,2509MHz,38.51W,[N/A] | 72,2470MHz,64.59W,[N/A] | 0 |
| 8 | D | 65,2398MHz,14.31W,[N/A] | 54,2502MHz,36.01W,[N/A] | 60,2502MHz,37.01W,[N/A] | 69,2476MHz,64.73W,[N/A] | 0 |

## Boot to boot: the first boot against its rerun (the rule's second pass)

| concurrency | arm | prose run1 | prose run2 | delta | code run1 | code run2 | delta | 8k run1 | 8k run2 |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | P | 70.7 | 71.8 | 1.016 | 113.8 | 115.4 | 1.014 | 2.675 | 2.588 |
| 2 | P | 105.7 | 105.6 | 0.999 | 175.7 | 176.1 | 1.002 | 2.604 | 2.590 |
| 4 | P | 166.4 | 165.2 | 0.993 | 254.8 | 258.1 | 1.013 | 2.585 | 2.606 |
| 6 | P | 206.1 | 206.6 | 1.002 | 315.7 | 314.2 | 0.995 | 2.596 | 2.571 |
| 8 | P | 243.2 | 239.2 | 0.984 | 367.0 | 380.8 | 1.038 | 2.635 | 2.583 |
| 1 | D | 66.5 | 65.6 | 0.986 | 115.1 | 113.5 | 0.986 | 2.963 | 2.954 |
| 2 | D | 99.5 | 100.0 | 1.005 | 168.8 | 169.5 | 1.004 | 2.963 | 2.954 |
| 4 | D | 154.6 | 155.8 | 1.008 | 242.1 | 239.5 | 0.989 | 3.107 | 2.889 |
| 6 | D | 187.2 | 185.9 | 0.993 | 281.0 | 282.8 | 1.006 | 2.961 | 3.033 |
| 8 | D | 209.1 | 214.0 | 1.023 | 323.8 | 326.7 | 1.009 | 3.030 | 3.034 |

## Token hashes every cell: P against D at the same prompt (kind, pass, j)

| concurrency | kind | rows | text sha equal | engine token_sha equal | P token shas | D token shas |
|---:|---|---:|---:|---:|---:|---:|
| 1 | prose | 3 | 0 | 0 | 3 | 3 |
| 1 | code | 3 | 0 | 0 | 3 | 3 |
| 2 | prose | 6 | 0 | 0 | 6 | 6 |
| 2 | code | 6 | 0 | 0 | 6 | 6 |
| 4 | prose | 12 | 0 | 0 | 12 | 12 |
| 4 | code | 12 | 2 | 2 | 10 | 12 |
| 6 | prose | 18 | 0 | 0 | 18 | 18 |
| 6 | code | 18 | 3 | 3 | 15 | 16 |
| 8 | prose | 24 | 0 | 0 | 24 | 24 |
| 8 | code | 24 | 5 | 5 | 19 | 21 |

## Cells not taken in this window

- the doc's under-load TTFT bracket (`load<C-1>`) at every level: idle only here
- the doc's 120k TTFT cases and its 1k thinking-on cell; 1k thinking-off is the control here
- RigMark: not run in this window
- the doc's 512-token cells are reproduced; no 256-token or short-prompt cells are reported
