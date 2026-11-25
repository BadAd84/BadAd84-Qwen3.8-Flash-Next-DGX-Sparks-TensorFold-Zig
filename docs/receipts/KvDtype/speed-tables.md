# KV dtype: speed, dev on bf16 against dev on fp8

## pool size at boot (the recipe banner and the boot's own KV plan line)

| cell | recipe banner | KV page groups plan line |
|---|---|---|
| D_bf16 c1 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 1 at once · 262144-token window · bf16 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) |
| D_bf16 c2 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 2 at once · 262144-token window · bf16 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) |
| D_bf16 c4 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 262144-token window · bf16 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) |
| D_bf16 c8 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · bf16 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) |
| D_fp8 c1 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 1 at once · 262144-token window · fp8 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) |
| D_fp8 c2 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 2 at once · 262144-token window · fp8 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) |
| D_fp8 c4 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 4 at once · 262144-token window · fp8 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) |
| D_fp8 c8 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision off · drafts MTP · port 8888 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) |

## decode, aggregate tok/s (per-stream median in parens), median of 3 passes

| C | kind | bf16 agg | bf16 per-stream | fp8 agg | fp8 per-stream | fp8/bf16 |
|---:|---|---:|---:|---:|---:|---:|
| 1 | prose | 68.5 | 68.47 | 66.8 | 66.83 | 0.975 |
| 1 | code | 111.1 | 111.06 | 115.9 | 115.93 | 1.043 |
| 2 | prose | 102.1 | 51.03 | 100.0 | 50.02 | 0.979 |
| 2 | code | 170.6 | 85.3 | 169.0 | 84.48 | 0.991 |
| 4 | prose | 155.7 | 40.06 | 154.9 | 40.33 | 0.995 |
| 4 | code | 245.9 | 62.53 | 240.5 | 61.72 | 0.978 |
| 8 | prose | 220.2 | 27.11 | 213.4 | 26.96 | 0.969 |
| 8 | code | 337.4 | 42.58 | 328.5 | 41.43 | 0.974 |

fp8/bf16 geometric mean over the 8 aggregate cells: **0.988**

## cold TTFT, s (median of 2 reps, idle) and the warm agent turn

| case | bf16 | fp8 | fp8/bf16 |
|---|---:|---:|---:|
| cold32k-off | 11.813 | 11.751 | 0.995 |
| cold8k-off | 3.125 | 2.974 | 0.952 |
| warm2k | 1.281 | 1.16 | 0.906 |


