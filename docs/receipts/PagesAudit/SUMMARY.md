# PagesAudit window summary

Numbers below are parsed from the window's own artifacts; `-` is not-reported, never zero.

## 1. Admission

| cell | arm | par | mode | boot rc | wall s | /health | pages | pages GiB | left GiB | cache | plan or refusal |
|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|---|
| on-c6-cold | on | 6 | cold | 0 | 52 | 200 | 238 | 17.14 | 22.4 | no prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 6 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 5 more taking 238 pages of 4096 r... |
| off-c6-cold | off | 6 | cold | 1 | 52 | 000 | - | - | - | - | tensorfold: --parallel 6 needs 31.60 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.42 GiB: serve --parallel 4, or lower --context |
| on-c6-resume | on | 6 | resume | 0 | 53 | 200 | 154 | 11.09 | 22.4 | a 3.1 GiB prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 6 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 5 more taking 154 pages of 4096 r... |
| off-c6-resume | off | 6 | resume | 1 | 52 | 000 | - | - | - | - | tensorfold: --parallel 6 needs 31.60 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.44 GiB: serve --parallel 4, or lower --context |
| on-c8-cold | on | 8 | cold | 0 | 52 | 200 | 238 | 17.14 | 22.4 | no prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 8 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 7 more taking 238 pages of 4096 r... |
| on-c8-resume | on | 8 | resume | 0 | 52 | 200 | 155 | 11.16 | 22.4 | a 3.1 GiB prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 8 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 7 more taking 155 pages of 4096 r... |
| off-c8-resume | off | 8 | resume | 1 | 52 | 000 | - | - | - | - | tensorfold: --parallel 8 needs 42.14 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.44 GiB: serve --parallel 4, or lower --context |
| on-c3-resume | on | 3 | resume | 0 | 52 | 200 | 150 | 10.80 | 22.4 | a 3.1 GiB prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 3 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 2 more taking 150 pages of 4096 r... |
| off-c3-resume | off | 3 | resume | 0 | 52 | 200 | none | 0.00 | 22.4 | a 6.0 GiB prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 3 streams at once, 5.27 GiB each at a 262144-token window (fp8 caches), of 22.4 GiB left after a 10.0 GiB reserve; prompts... |
| on-c4-cold | on | 4 | cold | 0 | 52 | 200 | 225 | 16.20 | 22.4 | no prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 4 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 3 more taking 225 pages of 4096 r... |
| off-c4-cold | off | 4 | cold | 0 | 52 | 200 | none | 0.00 | 22.4 | no prompt cache | [tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 80.46 GiB; 4 streams at once, 5.27 GiB each at a 262144-token window (fp8 caches), of 22.4 GiB left after a 10.0 GiB reserve; prompts... |

## 2. Cold TTFT (prompt cache off), client-measured

| cell | 32k med s | 32k range s | 128k med s | 128k range s | 128k prefill s | 128k server s | excluded |
|---|---:|---|---:|---|---:|---:|---:|
| on-c6-cold | 13.183 | 13.138-13.471 | 56.340 | 55.883-56.515 | 56.282 | 56.337 | 0 |
| off-c6-cold | - | --- | - | --- | - | - | - |
| on-c8-cold | 13.329 | 13.259-13.435 | 56.606 | 56.273-56.639 | 56.552 | 56.603 | 0 |
| on-c4-cold | 13.234 | 13.231-13.448 | 56.569 | 56.550-56.803 | 56.526 | 56.567 | 0 |
| off-c4-cold | 13.300 | 13.205-13.476 | 56.621 | 56.389-56.764 | 56.566 | 56.618 | 0 |

## 3. Decode at the level (2 passes a kind, 512 tokens a request)

| cell | kind | per-stream med s^-1 | range | aggregate s^-1 | tok/wall | tokens |
|---|---|---:|---|---:|---:|---:|
| on-c6-cold | code | 33.895 | 33.360-34.430 | 200.800 | 179.950 | 6144 |
| on-c6-cold | prose | 23.215 | 22.180-24.250 | 134.700 | 120.400 | 5975 |
| on-c8-cold | code | 29.515 | 28.900-30.130 | 230.900 | 202.400 | 8192 |
| on-c8-cold | prose | 19.695 | 19.290-20.100 | 153.600 | 137.050 | 7900 |
| on-c4-cold | code | 39.730 | 39.190-40.270 | 157.350 | 141.750 | 4096 |
| on-c4-cold | prose | 26.640 | 26.350-26.930 | 103.950 | 94.900 | 3943 |
| off-c4-cold | code | 39.595 | 39.290-39.900 | 157.950 | 142.250 | 4096 |
| off-c4-cold | prose | 26.725 | 26.390-27.060 | 104.150 | 94.950 | 3943 |

## 4. Resume: turn 2 of a kept conversation

| cell | A1 prompt | A1 ttft s | A2 cached | A2 ttft s | T2 cached | T2 cached past prompt | T2 ttft s | A3 cached | verdict |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| on-c6-resume | 129248 | 56.791 | 129241 | 0.158 | 129241 | -7 | 0.403 | 0 | PASS |
| off-c6-resume | - | - | - | - | - | - | - | - | tensorfold: --parallel 6 needs 31.60 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.44 GiB: serve --parallel 4, or lower --context |
| on-c8-resume | 129250 | 57.179 | 129243 | 0.178 | 129243 | -7 | 0.353 | 0 | PASS |
| off-c8-resume | - | - | - | - | - | - | - | - | tensorfold: --parallel 8 needs 42.14 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.44 GiB: serve --parallel 4, or lower --context |
| on-c3-resume | 129250 | 57.464 | 129243 | 0.176 | 129243 | -7 | 0.344 | 0 | PASS |
| off-c3-resume | 129252 | 57.382 | 129245 | 0.192 | 129245 | -7 | 0.341 | 129245 | PASS |

## 5. The serve's own `done` lines and /stats

| cell | done lines | cached requests | queued>0 | queued max s | tok/s median | /stats max waiting | /stats max running | prompt cache (states / bytes / hits / misses) |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| on-c6-cold | 31 | 0 | 20 | 0.144 | 29.9 | 0 | 6 | None / None / None / None |
| off-c6-cold | - | - | - | - | - | - | - | None / None / None / None |
| on-c6-resume | 5 | 3 | 0 | 0.000 | 45.6 | 0 | 1 | 1 / 115678464 / 3 / 2 |
| off-c6-resume | - | - | - | - | - | - | - | None / None / None / None |
| on-c8-cold | 39 | 0 | 28 | 0.146 | 26.2 | 0 | 8 | None / None / None / None |
| on-c8-resume | 5 | 3 | 1 | 0.001 | 61.8 | 0 | 1 | 1 / 115678464 / 3 / 2 |
| off-c8-resume | - | - | - | - | - | - | - | None / None / None / None |
| on-c3-resume | 5 | 3 | 0 | 0.000 | 55.0 | 0 | 1 | 1 / 115678464 / 3 / 2 |
| off-c3-resume | 5 | 4 | 0 | 0.000 | 42.1 | 0 | 1 | 4 / 5068264960 / 1 / 1 |
| on-c4-cold | 23 | 0 | 10 | 0.129 | 30.9 | 0 | 4 | None / None / None / None |
| off-c4-cold | 23 | 0 | 11 | 0.141 | 31.4 | 0 | 4 | None / None / None / None |

## 6. On against off at the same level

Cold TTFT and decode deltas are `on` against `off`; a direction is claimed only when both cells ran and the delta is over 2 percent (one fresh boot a cell, so a sub-2-percent gap is LEVEL).

| level | mode | metric | on | off | delta % | reading |
|---|---|---|---:|---:|---:|---|
| 3 | resume | 32k TTFT med s | - | - | - | unmeasured |
| 3 | resume | 128k TTFT med s | - | - | - | unmeasured |
| 3 | resume | decode prose agg s^-1 | - | - | - | unmeasured |
| 3 | resume | decode code agg s^-1 | - | - | - | unmeasured |
| 3 | resume | T2 resume ttft s | 0.344 | 0.341 | 0.9 | LEVEL |
| 3 | resume | A2 resume cached tokens | 129243 | 129245 | -0.0 | LEVEL |
| 4 | cold | 32k TTFT med s | 13.234 | 13.300 | -0.5 | LEVEL |
| 4 | cold | 128k TTFT med s | 56.569 | 56.621 | -0.1 | LEVEL |
| 4 | cold | decode prose agg s^-1 | 104.0 | 104.2 | -0.2 | LEVEL |
| 4 | cold | decode code agg s^-1 | 157.3 | 157.9 | -0.4 | LEVEL |
| 4 | cold | T2 resume ttft s | - | - | - | unmeasured |
| 4 | cold | A2 resume cached tokens | - | - | - | unmeasured |
| 6 | cold | 32k TTFT med s | 13.183 | - | - | unmeasured |
| 6 | cold | 128k TTFT med s | 56.340 | - | - | unmeasured |
| 6 | cold | decode prose agg s^-1 | 134.7 | - | - | unmeasured |
| 6 | cold | decode code agg s^-1 | 200.8 | - | - | unmeasured |
| 6 | cold | T2 resume ttft s | - | - | - | unmeasured |
| 6 | cold | A2 resume cached tokens | - | - | - | unmeasured |
| 6 | resume | 32k TTFT med s | - | - | - | unmeasured |
| 6 | resume | 128k TTFT med s | - | - | - | unmeasured |
| 6 | resume | decode prose agg s^-1 | - | - | - | unmeasured |
| 6 | resume | decode code agg s^-1 | - | - | - | unmeasured |
| 6 | resume | T2 resume ttft s | 0.403 | - | - | unmeasured |
| 6 | resume | A2 resume cached tokens | 129241 | - | - | unmeasured |
| 8 | resume | 32k TTFT med s | - | - | - | unmeasured |
| 8 | resume | 128k TTFT med s | - | - | - | unmeasured |
| 8 | resume | decode prose agg s^-1 | - | - | - | unmeasured |
| 8 | resume | decode code agg s^-1 | - | - | - | unmeasured |
| 8 | resume | T2 resume ttft s | 0.353 | - | - | unmeasured |
| 8 | resume | A2 resume cached tokens | 129243 | - | - | unmeasured |

## 7. GPU temperature at each timed window (C, from nvidia-smi)

| cell | boot start | before TTFT | after TTFT | after decode | before resume | after resume |
|---|---|---|---|---|---|---|
| on-c6-cold | 41 | 46 | 70 | 65 | - | - |
| off-c6-cold | 43 | - | - | - | - | - |
| on-c6-resume | 45 | - | - | - | 47 | 70 |
| off-c6-resume | 55 | - | - | - | - | - |
| on-c8-cold | 54 | 53 | 73 | 65 | - | - |
| on-c8-resume | 56 | - | - | - | 53 | 72 |
| off-c8-resume | 65 | - | - | - | - | - |
| on-c3-resume | 66 | - | - | - | 59 | 75 |
| off-c3-resume | 64 | - | - | - | 58 | 70 |
| on-c4-cold | 66 | 57 | 73 | 66 | - | - |
| off-c4-cold | 62 | 57 | 75 | 66 | - | - |

## 8. The pool's own post-run lines (from the serve log)

- none: the flashnext pool prints its plan and its KV page groups at load and no per-request
  page or map counter during the run; the waits it does expose are `/stats.waiting` (section 5)
  and the serve's own `done ... queued=` line.

## 9. Exactness across arms at one level (decode reply shas)

- par 4: 16 of 16 per-request reply shas identical between the arms

