# Four control-paired arms: depth, the round, the chunk and the warm pool (spark6)

Status: the window ran in one hold of `~/work/gpu.lock` on 2026-11-22 (queued 21:55:07, taken 22:41:22, RUN-DONE 23:18:21, 36 min, driver exit 0), nine boots all ENV-OK, production restored at the end (health 200, pinned image). The depth pair at 15 is 0.815 / 0.840 / 0.791 on prose and 1.046 / 1.038 / 0.956 on code; the shipped 6/8 control is within one percent of every cell, so the depth setting is not the prose gap. The four-stream counters say why: ours drafts 1.92 tokens a round on prose against production's 3.03 while accepting the same fraction (76.0 against 75.0 percent) and paying less a round (47.0 against 52.3 ms), so we draft less, not accept less or pay more. The 4096 chunk is 3.6 / 2.5 percent faster at 8k / 32k than 3072, which leaves 14.1 / 18.0 percent to production: the chunk is a small part, not the gap. The 192 value is the rows a page, not a page count: the pool stays 23.60 GiB, the planner keeps no prompt cache, the three warm samples are 43.93 to 44.09 s with cached 0 (n 0, excluded 3), and the trade is the whole memory budget. One 8x8 PNG returned 200 "Red" in 0.31 s: the image serves an image, and the boot's absent helper line is not a capability gap.

Window identity: queued 2026-11-22T21:55:07+00:00 behind the KvTierW2 lane, lock taken 22:41:22 (pid 1424486), RUN-DONE 23:18:21, elapsed 36 min, driver exit 0, OUTER-RESTORE not needed. Host kernel `7.0.0-1019-nvidia-64k`, Ubuntu 24.04.5 LTS, NVIDIA GB10 driver 580.178.04, 123 GiB RAM. Preflight: production `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea77ee...` healthy on :8888; our image `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `sha256:578911ca84d4...`, manifest `ab6389fc2ab6...`, source `1ece6e6d...+r5-0001-0020+int4-0021-0022`; the recipe `start.sh` `51b74c92b926fe26`, `scripts/config.sh` `f7cc1463e9402132`, `stop.sh` `57b5cd39b89caeb7`. Production restored at 23:18:21: `PROD-BOOT rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee...`, `PROD-IMAGE-OK`, `EXIT-DONE ... health 200` with the same image, `OUTER-RESTORE not needed, health 200`.

The driver is `driver.sh` sha256 `451cda9526023c9c608a39a732f1d47d92af15102f9f99d2d4ddba5a7ce36665`; the payload's own `in/SHA256SUMS` verified on the box and locally, both ways.

## 1. What ran

The hold's order, each boot stopped before the next:

1. `P15a`: production from its own launcher (its env `TF_FLASHNEXT_DEPTH=15`), shot at 1, 4 and 8 streams, prose and code.
2. `D15a`: our image at `TF_FLASHNEXT_DRAFTS=15` and `TF_FLASHNEXT_DRAFTS_GREEDY=15`, 4096 pages, production's 54 names, the same decode cells.
3. `P15b`, then `D15b`: the same pair again. A cell whose runs interleave with a mean gap past one percent gets one more pair, `P15c` and `D15c`.
4. `C3a`: our image at the recipe's shipped depth (`TF_FLASHNEXT_DRAFTS=6`, greedy 8) with the decode cells and the first cold-TTFT control boot at the tree's default chunk of 3072 rows.
5. `C4a` (chunk `TF_FLASHNEXT_CHUNK=4096` and `TF_FLASHNEXT_CHUNK_SOLO=4096`), `C3b` (default 3072), `C4b` (4096): cold TTFT at 1k, 8k and 32k, thinking off, idle. A flagged pair gets `C4c` and `C3c`.
6. `W192`: our image at `TF_FLASHNEXT_KV_PAGES=192` (the rows a page, not a page count: the planner takes 6990 pages of 192 rows), the cold 1k cell, the warm +2k turn on a kept 100k conversation, then one image request for the vision fact.
7. Production restarted from its launcher and verified (`/health` 200, pinned image, `PROD-IMAGE-OK`).

Every decode shot is the same harness and the same prompt set: 256 greedy tokens a request, three reps, the chat (prose) and code prompts, aggregate tokens a second over the batch. Every boot's container environment is read back and audited against the expected set; every boot's planner lines are recorded.

## 2. The levers, and what the pair holds constant

Production's engine (`/opt/tensorfold/native/bin/tensorfold-native`) carries `TF_FLASHNEXT_DEPTH` and reads it in
`cuda_native.zig` with a default of 15; its launcher exports `TF_FLASHNEXT_DEPTH=15`, so production serves at depth
15. Our engine carries `TF_FLASHNEXT_DRAFTS` (default 6) and `TF_FLASHNEXT_DRAFTS_GREEDY` (default 8), both clamped
to 1 through 15, and has no reader for `TF_FLASHNEXT_DEPTH` (its only DEPTH string is the diagnostic
`TF_FLASHNEXT_DEPTH_LOG`). The depth pair is therefore production at its own 15 against ours at
`TF_FLASHNEXT_DRAFTS=15 TF_FLASHNEXT_DRAFTS_GREEDY=15`, both at production's served shape; the shipped-depth anchor
is ours at the recipe's 6 and greedy 8.

The two engines do not share the whole draft block: production's engine reads `TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7`,
`TF_FLASHNEXT_DRAFT_CONTINUE=0.20` and `TF_FLASHNEXT_DRAFT_PROPOSE=0.05`; our engine carries none of those names and
instead reads `TF_FLASHNEXT_SHARED_DRAFTS` (default 1). Both read `TF_FLASHNEXT_CONFIDENCE`, and both boots inherit
production's -0.15. The pair therefore isolates the numeric depth, while the counters carry the shared-round policy
difference.

The prefill names differ too: production's engine reads `TF_FLASHNEXT_PREFILL_ROWS` (its launcher exports 4096); our
engine reads `TF_FLASHNEXT_CHUNK` (default 3072, 1 through 16384) and `TF_FLASHNEXT_CHUNK_SOLO` (unset = the larger
of CHUNK and 8192 on a one-stream server, else CHUNK). The prefill arm sets both of ours to 4096 against the tree's
default 3072; on an idle single request the solo setting is the one that applies.

The one added setting beyond production's 54 names on every dev boot is the page pool:
`TF_FLASHNEXT_KV_PAGES` (4096 for the shape arms; 192 for the warm boot, where the engine reads it as the rows a page, not a page count). The recipe's own sixteen lever defaults
(15 in `in/dev-defaults.env` plus `TF_FLASHNEXT_DRAFTS`) are expected, not drift, and the environment audit treats
them as the expected set. Every boot's readback and audit are in section 3.

## 3. The tables

## Depth-matched decode, production at DEPTH=15 against ours at DRAFTS=15 greedy 15

A cell is every run's aggregate tokens a second, 256 greedy tokens a request, three reps in each run.
The noise rule: slower only when both runs of one arm are under both runs of the other and the mean gap
passes one percent; a single run a side is indicative.

| kind | streams | production runs | production mean | dev runs | dev mean | dev / prod | verdict |
|---|---:|---|---:|---|---:|---:|---|
| chat | 1 | 85.7, 85.9 | 85.8 | 69.9, 69.9 | 69.9 | 0.815 | slower |
| chat | 4 | 243.6, 243.0 | 243.3 | 204.1, 204.7 | 204.4 | 0.840 | slower |
| chat | 8 | 407.6, 407.3 | 407.5 | 322.3, 322.3 | 322.3 | 0.791 | slower |
| code | 1 | 90.3, 93.1 | 91.7 | 95.9, 95.9 | 95.9 | 1.046 | faster |
| code | 4 | 262.8, 262.6 | 262.7 | 272.7, 272.9 | 272.8 | 1.038 | faster |
| code | 8 | 441.3, 439.4 | 440.4 | 421.2, 420.9 | 421.0 | 0.956 | slower |

- chat: geometric mean dev/prod 0.815 over 1, 4 and 8 streams
- code: geometric mean dev/prod 1.013 over 1, 4 and 8 streams

Ours at the shipped depth (DRAFTS=6, greedy 8) on the same production runs, one boot, indicative:

| kind | streams | production mean | shipped run | shipped / prod |
|---|---:|---:|---:|---:|
| chat | 1 | 85.8 | 69.2 | 0.807 |
| chat | 4 | 243.3 | 204.9 | 0.842 |
| chat | 8 | 407.5 | 322.6 | 0.792 |
| code | 1 | 91.7 | 95.6 | 1.043 |
| code | 4 | 262.7 | 272.8 | 1.038 |
| code | 8 | 440.4 | 420.9 | 0.956 |

## Round accounting at four streams, from each engine's own done lines

Each row is the twelve 256-token requests of that kind in the four-stream cell: rounds a request,
drafted and accepted draft tokens a request, the acceptance rate over all twelve, tokens a round, and
milliseconds a round measured on the client's own first-to-last span (the server's decode field where
the engine prints one).

| arm | engine / depth | kind | requests | rounds | drafted | accepted | acceptance | drafted/round | accepted/round | tokens/round | ms/round | ms/round (server) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P15a | production, DEPTH=15 | chat | 12 | 78 | 2832 | 2124 | 75.0% | 3.03 | 2.27 | 3.28 | 52.3 | - |
| P15a | production, DEPTH=15 | code | 12 | 68 | 2985 | 2244 | 75.2% | 3.66 | 2.75 | 3.76 | 55.7 | - |
| P15b | production, DEPTH=15 | chat | 12 | 78 | 2832 | 2124 | 75.0% | 3.03 | 2.27 | 3.28 | 52.2 | - |
| P15b | production, DEPTH=15 | code | 12 | 68 | 2978 | 2244 | 75.4% | 3.65 | 2.75 | 3.76 | 55.7 | - |
| D15a | ours, DRAFTS=15 greedy 15 | chat | 12 | 104 | 2400 | 1824 | 76.0% | 1.92 | 1.46 | 2.46 | 47.0 | 47.0 |
| D15a | ours, DRAFTS=15 greedy 15 | code | 12 | 73 | 2340 | 2184 | 93.3% | 2.67 | 2.49 | 3.51 | 50.3 | 50.3 |
| D15b | ours, DRAFTS=15 greedy 15 | chat | 12 | 104 | 2400 | 1824 | 76.0% | 1.92 | 1.46 | 2.46 | 46.8 | 46.8 |
| D15b | ours, DRAFTS=15 greedy 15 | code | 12 | 73 | 2340 | 2184 | 93.3% | 2.67 | 2.49 | 3.51 | 50.2 | 50.2 |
| C3a | ours, shipped DRAFTS=6 greedy 8 | chat | 12 | 104 | 2400 | 1824 | 76.0% | 1.92 | 1.46 | 2.46 | 46.7 | 46.7 |
| C3a | ours, shipped DRAFTS=6 greedy 8 | code | 12 | 73 | 2340 | 2184 | 93.3% | 2.67 | 2.49 | 3.51 | 50.0 | 50.0 |

Counter cross-check: the sum of the twelve-plus-twelve done lines against the /metrics mtp counters
before and after the same four-stream probe. The metrics also carry the probe's two 16-token warm-ups.

| arm | log drafted | metrics drafted | log accepted | metrics accepted |
|---|---:|---:|---:|---:|
| P15a | 5817 | 5841 | 4368 | 4387 |
| P15b | 5810 | 5834 | 4368 | 4387 |
| D15a | 4740 | 4764 | 4008 | 4028 |
| D15b | 4740 | 4764 | 4008 | 4028 |
| C3a | 4740 | 4764 | 4008 | 4028 |

## Prefill at chunk 4096 against the default 3072, cold TTFT idle, thinking off

Seconds, the median of each run's own summary (three samples a run). Higher is worse; the verdict is the
same noise rule with the sign flipped.

| case | control runs (3072) | control mean | test runs (4096) | test mean | test / control | verdict |
|---|---|---:|---|---:|---:|---|
| cold1k-off | 0.485, 0.481 | 0.483 | 0.464, 0.462 | 0.463 | 0.959 | faster |
| cold8k-off | 3.179, 3.153 | 3.166 | 3.051, 3.055 | 3.053 | 0.964 | faster |
| cold32k-off | 12.984, 12.849 | 12.916 | 12.597, 12.590 | 12.593 | 0.975 | faster |

- cold1k-off: test/control 0.959
- cold8k-off: test/control 0.964
- cold32k-off: test/control 0.975

## Warm turn on a kept 100k conversation, 192-page pool

- cold1k-off: n 3 median 0.476 s p90 0.479 s excluded 0 (production's recorded warm2k median is 1.123 s)
- warm2k: n 0 median - s p90 - s excluded 3 (production's recorded warm2k median is 1.123 s)
  `sample warm2k idle ttft 43.934 admit 0.003 queue - prefill 43.930 other 0.000 server 43.932 prompt 102379 cached 0 first content others 0 NOTWARM`
  `sample warm2k idle ttft 43.980 admit 0.003 queue - prefill 43.977 other 0.000 server 43.979 prompt 102332 cached 0 first content others 0 NOTWARM`
  `sample warm2k idle ttft 44.087 admit 0.005 queue - prefill 44.081 other 0.000 server 44.085 prompt 102353 cached 0 first content others 0 NOTWARM`
  plan: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 6990 pages of 192 rows (23.60 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
  plan: `KV page groups: one page 3.46 MiB, 192 rows of the full group; full: layers not named, 18.44 KiB a token, 192 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 113 pages, 3.25 MiB padding (0.8 %); snapshot, outside the pool: 110.29 MiB on 32 pages, 348.00 KiB padding (0.3 %)`
  trade: 6,990 pages x 192 rows = 1,342,080 positions, 64.0% of the eight-stream 262,144-token shape (2,097,152); the plan says no prompt cache. The KV_PAGES value is the rows a page, not a page count; the pool's bytes are the budget's, so the 192 value changes granularity, not the pool's size.

## Vision fact

- status 200 in 0.31 s, image 74 bytes
- body: `{"id": "chatcmpl-fd73672134b2421a1e4078bc3e59be73", "object": "chat.completion", "created": 1795389411, "model": "Qwen3.8-Flash-Next", "choices": [{"index": 0, "message": {"role": "assistant", "content": "Red"}, "finish_reason": "stop"}], "usage": {"prompt_tokens": 89, "completion_tokens": 2, "total_tokens": 91, "prompt_tokens_details": {"cached_tokens": 0}, "completion_tokens_details": {"reasoning_tokens": 0}}, "exact_mode": "exact", "tensorfold": {"enable_thinking": false, "reasoning_effort": "none", "engine": "lanes", "tokens_per_second": 21.28476365951836, "seconds": 0.046981964, "prefill_seconds": 0.248152692, "prefill_widths": [], "prefill_raised": [], "time_to_first_token": 0.249565521, "sampling": "greedy", "drafts": true, "token_sha": "d527abcfa8c5", "token_sha256": "d527abcfa8c5d`
- log: `Container image Copyright (c) 2026, NVIDIA CORPORATION & AFFILIATES. All rights reserved.`
- log: `[tensorfold] warning: libturbojpeg.so.0 is required for JPEG inputs (--vision); install libjpeg-turbo 3.1.4.1 and set TENSORFOLD_LIBTURBOJPEG to its file, or put it on the documented loader path`
- log: `[tensorfold] warning: libwebpdecoder.so.3 is required for WebP inputs (--vision); install libwebp 1.6.0 and set TENSORFOLD_LIBWEBP to its decoder file, or put it on the documented loader path`

## Environment and boot readback

| arm | image | boot | ENVAUDIT | banner |
|---|---|---|---|---|
| C3a | qr-b-r5int4- | wall_s 145.7 boot_rc 0 | ENVAUDIT ok expected 71 read 71 match 70 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| C3b | qr-b-r5int4- | wall_s 145.7 boot_rc 0 | ENVAUDIT ok expected 71 read 71 match 70 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| C4a | qr-b-r5int4- | wall_s 151.7 boot_rc 0 | ENVAUDIT ok expected 73 read 73 match 72 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| C4b | qr-b-r5int4- | wall_s 145.7 boot_rc 0 | ENVAUDIT ok expected 73 read 73 match 72 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| D15a | qr-b-r5int4- | wall_s 142.7 boot_rc 0 | ENVAUDIT ok expected 72 read 72 match 71 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| D15b | qr-b-r5int4- | wall_s 142.7 boot_rc 0 | ENVAUDIT ok expected 72 read 72 match 71 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |
| P15a | zmerge8-kfix | - | ENVAUDIT ok expected 54 read 54 match 54 allow 0 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8888 |
| P15b | zmerge8-kfix | - | ENVAUDIT ok expected 54 read 54 match 54 allow 0 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8888 |
| W192 | qr-b-r5int4- | wall_s 142.7 boot_rc 0 | ENVAUDIT ok expected 71 read 71 match 70 allow 1 mismatch 0 missing 0 extra 0 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 |

## Planner lines per boot

- C3a: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- C3a: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- C3b: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- C3b: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- C4a: `8 streams at once, the engine's own at a 262144-token window (5.09 GiB, in the model's), 7 more taking 320 pages of 4096 rows (23.05 GiB) as they need them, 84 MiB fixed each, of 28.7 GiB left after a 10.0 GiB reserve; prompts in passes of up to 4096 rows, no prompt cache; own glue kernels`
- C4a: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 407.39 MiB on 6 pages, 35.11 MiB padding (7.9 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- C4b: `8 streams at once, the engine's own at a 262144-token window (5.09 GiB, in the model's), 7 more taking 320 pages of 4096 rows (23.05 GiB) as they need them, 84 MiB fixed each, of 28.7 GiB left after a 10.0 GiB reserve; prompts in passes of up to 4096 rows, no prompt cache; own glue kernels`
- C4b: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 407.39 MiB on 6 pages, 35.11 MiB padding (7.9 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- D15a: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D15a: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- D15b: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D15b: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- P15a: `prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)`
- P15a: `vision: image and video input on this GPU, a 0.84 GiB tower (helper pid 179; {"torch":"2.13.0a0+9186a08b2c.nv26.07","transformers":"5.17.0","pillow":"12.3.0","numpy":"2.1.0","av":"19.0.1"}; self-test b519f02192431f6965510b499bf1cd22474d9298262730d78505b2658fa51678)`
- P15b: `prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)`
- P15b: `vision: image and video input on this GPU, a 0.84 GiB tower (helper pid 178; {"torch":"2.13.0a0+9186a08b2c.nv26.07","transformers":"5.17.0","pillow":"12.3.0","numpy":"2.1.0","av":"19.0.1"}; self-test b519f02192431f6965510b499bf1cd22474d9298262730d78505b2658fa51678)`
- W192: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 6990 pages of 192 rows (23.60 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- W192: `KV page groups: one page 3.46 MiB, 192 rows of the full group; full: layers not named, 18.44 KiB a token, 192 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 113 pages, 3.25 MiB padding (0.8 %); snapshot, outside the pool: 110.29 MiB on 32 pages, 348.00 KiB padding (0.3 %)`

## Production restored, and the window's own end

- [2026-11-22T22:43:00+00:00] PROD-BOOT rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f mem_avail 31
- [2026-11-22T22:43:00+00:00] PROD-IMAGE-OK tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
- [2026-11-22T22:49:33+00:00] PROD-BOOT rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f mem_avail 30
- [2026-11-22T22:49:33+00:00] PROD-IMAGE-OK tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
- [2026-11-22T23:16:53+00:00] FOREIGN-SUMMARY C3a=0 C3b=0 C4a=0 C4b=0 D15a=0 D15b=0 P15a=857 P15b=859 W192=0 
- [2026-11-22T23:18:21+00:00] PROD-BOOT rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f mem_avail 30
- [2026-11-22T23:18:21+00:00] PROD-IMAGE-OK tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
- [2026-11-22T23:18:21+00:00] RUN-DONE 2026-11-22T23:18:21+00:00 elapsed 36 min
- [2026-11-22T23:18:21+00:00] EXIT-DONE 2026-11-22T23:18:21+00:00 health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
- OUTER-RESTORE not needed, health 200 2026-11-22T23:18:21+00:00

## Flags for a rerun

- none

## 4. What the arms say

### 1. The depth pair says the prose gap is not the depth setting

At the numeric depth of 15 on both engines, ours reads 69.9, 204.4 and 322.3 tokens a second on prose at 1, 4 and 8 streams against production's 85.8, 243.3 and 407.5 (0.815, 0.840, 0.791; all slower). On code ours reads 95.9, 272.8 and 421.0 against 91.7, 262.7 and 440.4 (1.046, 1.038, 0.956; faster at 1 and 4, slower at 8). The geometric means are 0.815 on prose and 1.013 on code. The shipped-depth control (`C3a`, DRAFTS=6 and greedy 8) is inside one percent of every one of those cells (prose 0.807, 0.842, 0.792; code 1.043, 1.038, 0.956), and its four-stream counters are digit-identical to the 15/15 boots. Raising our chain from 6/8 to 15/15 changes nothing measurable: the depth number is not the prose gap.

### 2. The round accounting: we draft less, we do not accept less or pay more

From each engine's own `done` lines at four streams (twelve 256-token requests a kind; both boots of ours identical to the digit):

| engine | kind | rounds | drafted | accepted | acceptance | drafted/round | tokens/round | ms/round |
|---|---|---:|---:|---:|---:|---:|---:|---:|
| production, DEPTH=15 | prose | 78 | 2832 | 2124 | 75.0% | 3.03 | 3.28 | 52.3 |
| ours, DRAFTS=15 | prose | 104 | 2400 | 1824 | 76.0% | 1.92 | 2.46 | 47.0 |
| production, DEPTH=15 | code | 68 | 2985 | 2244 | 75.2% | 3.66 | 3.76 | 55.7 |
| ours, DRAFTS=15 | code | 73 | 2340 | 2184 | 93.3% | 2.67 | 3.51 | 50.3 |

The prose rate ratio decomposes: tokens a round 2.46/3.28 = 0.750, milliseconds a round 47.0/52.3 = 0.899, and 0.750/0.899 = 0.834 against the measured 0.840. We draft 1.92 tokens a round where production drafts 3.03, we accept a slightly higher fraction (76.0 against 75.0 percent), and our round is 5.3 ms cheaper. The prose gap is the drafting volume a round. On code the same decomposition (3.51/3.76 = 0.934; 50.3/55.7 = 0.903; 1.034 against the measured 1.038) explains why we win at 1 and 4 streams: we draft fewer but accept 93.3 against 75.2 percent, and the cheaper round carries the rate.

Production's 15 is a cap its adaptive/shared rule fills to 3.03 and 3.66 drafts a round; our tree reads the depth settings, but its stop/shared rule truncates the chain at 1.92 and 2.67. The lever to close the prose gap is the chain/shared stop policy, not the depth number. Production's `TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7` has no reader in our tree; ours reads `TF_FLASHNEXT_SHARED_DRAFTS`.

The `/metrics` cross-check agrees with the logs: the deltas exceed the 256-token sums by the probes' two 16-token warm-ups (24 drafted on every arm, 19 to 20 accepted), so the counters quoted are the engines' own.

### 3. Prefill: the chunk height is a small part, not the gap

At chunk 4096 against the default 3072, both boots an arm, cold TTFT idle: 1k 0.463 against 0.483 (0.959), 8k 3.053 against 3.166 (0.964), 32k 12.593 against 12.916 (0.975); all three cells are decisively faster. The planner readback confirms 4096 against 3072 rows a pass. Production's recorded 2.675 and 10.674 s are still 1.141 and 1.180 of our 4096 test: this window's control gaps are 18.4 and 21.0 percent, the 4096 test leaves 14.1 and 18.0, so the chunk buys 4.3 and 3.0 points of the gap. It is a small part of the prefill gap, not its cause; the rest is the engine and its kernels, outside this arm.

### 4. The warm turn: the 192 value is a page height, and the pool keeps no cache

`TF_FLASHNEXT_KV_PAGES=192` did not make a 192-page pool: the planner's own line says "one page 3.46 MiB, 192 rows of the full group; 7 more taking 6990 pages of 192 rows (23.60 GiB)". The value is the rows a page; the pool's bytes are the budget's, and 6990 x 192 = 1,342,080 positions is the same ~1.34M positions (64.0 percent of the 8 x 262,144 shape) as the main arms' 327 pages x 4096 rows. The planner says "no prompt cache" on both: the whole-prompt cache needs memory after the seven extra streams' 23.60 GiB of the 29.2 GiB left, with the engine's own stream in the model's 5.07 GiB and 10.0 GiB kept free.

The warm samples are therefore no-cache repeats: 43.934, 43.980 and 44.087 s for the 102,379-token prompt, `cached 0`, each flagged NOTWARM and excluded (n 0, excluded 3). The prefill is the whole 102k at about 2.33k tokens a second. Production's recorded cache-backed 1.123 s is 39 times faster; the two are not a like-for-like warm comparison. The trade is the shape: fitting eight 262,144-token streams consumes the memory budget, and this page-height switch cannot buy cache room. A cache-bearing warm turn needs a smaller pool budget or a smaller shape, neither of which this arm could set while keeping production's shape. The 192-page pool the earlier report named was a misreading of the lever, and this window measures what it actually does.

### 5. Vision: the image serves an image

With `--vision --vision-max-images 50 --vision-max-videos 4 --vision-image-tokens 16384` in the argv and the banner saying vision on, one 8x8 PNG request returned 200 in 0.312 s with content "Red", 89 prompt tokens, prefill 0.248 s and `rounds=1 accepted=2/2`. The boot log's only vision lines are the two decoder warnings; there is no `[vision-helper]` line, and the request works anyway. This is neither a missing helper in the image nor a flag being ignored: the image serves a PNG on this build. JPEG and WebP are the exceptions, because libturbojpeg and libwebpdecoder are not in the image and the boot says so. The prior window's boot-time observation is corrected: the absent helper line did not mean no vision.

### 6. Environment and restore

Every one of the nine boots is ENV-OK: production 54 of 54; our shipped and warm boots 71 (54 production names, 15 recipe defaults, `KV_PAGES` and `DRAFTS`); our depth boots 72 (+`DRAFTS_GREEDY`); our chunk boots 73 (+`CHUNK` and `CHUNK_SOLO`), with the one allowed `TENSORFOLD_CUDA_KERNELS=native` on every dev boot and no mismatch, missing or extra name. Production was restored at 23:18:21 with the pinned image and /health 200 (section 3's lines). The production-serving cells saw 857 and 859 nonlocal request lines (sparkDash's GET polls); our arms saw none.

Harness note: the driver writes the ttft probe as `ttft_cold.out` and `ttft_warm.out`; the analyzer's first version read `ttft.out`. The analyzer was replaced atomically on the box at 23:02:02 (sha256 `dbc09e235f54f4064508d38bac604d90438d09f0bc60b5b8c99fdde06470156f`) before the prefill flag check, the staged `in/SHA256SUMS` regenerated and verified, and the change recorded in `out/run.log` as `HARNESS-FIX` (its timestamp is the literal `$(date -Is)`, an escaping slip in the append). The measurement arms are unaffected; the final analysis reads the ttft files directly. The final local rendering adds the warm sample and page-height trade output (sha256 8dc92a44c1a14fffc307f3145732c2a22bcd63262dce922259a06223486d3c33); the flag decisions were made by the box copy dbc09e... .

## 5. What this window does not prove

- The depth pair matches the numeric depth (production's engine reads `TF_FLASHNEXT_DEPTH=15`; ours reads
  `TF_FLASHNEXT_DRAFTS=15` and `TF_FLASHNEXT_DRAFTS_GREEDY=15`) but not the rest of production's draft block:
  production's `TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7`, `_DRAFT_CONTINUE=0.20` and `_DRAFT_PROPOSE=0.05` have no reader
  in our tree, and our `TF_FLASHNEXT_SHARED_DRAFTS` rule has no counterpart in production's. The one- and two-engine
  cells measure the blocks as served; only the numeric cap is matched.
- The prefill arm sets our `TF_FLASHNEXT_CHUNK` and `_CHUNK_SOLO` to 4096 against the default 3072. Production's
  engine reads `TF_FLASHNEXT_PREFILL_ROWS=4096`, a different name; the two names' exact equivalence is not proven
  here, only the row count each engine is given.
- The cache-bearing warm turn is not measured: the named 192 value is the rows a page, not a page count; the
  pool stayed 23.60 GiB and the planner kept no prompt cache, so the three warm samples are the no-cache 43.9 s
  repeats (n 0, excluded 3). Other pool sizes, the loaded variant, and conversations longer than 100k remain
  unmeasured, and the 1.123 s production reference is cache-backed, so it is not like-for-like against 43.9 s.
- Only PNG is exercised for vision: the boot warns that libturbojpeg and libwebpdecoder are absent, so JPEG and WebP
  inputs are not testable on this image, and image or video cells are not speed cells.
- Production's warm reference (1.123 s, the mean of 1.254, 1.074 with n 2 and 1.041 s) is the prior window's
  recorded value, not a fresh production warm boot in this window.
- The round accounting uses the harness's chat and code prompts at four streams, not an agent's 100k-turn traffic.
- Thinking off is requested on both sides and verified on ours only; the harness labels production's request
  `off requested (unverified)` while both requests carry the same `chat_template_kwargs`.
- The environment audit checks the container's environment, not that the engine consumed every name; the engine's
  readers are evidenced separately by the binary strings and the source.

## 6. Where every number comes from

| claim | source |
|---|---|
| arms, order, images, boot walls, banners, pool | `out/<arm>/image-id.txt`, `boot_time.txt`, `banner.txt`, `pool.txt`; the `PREFLIGHT`/`BOOT`/`PROD-BOOT` lines in `out/run.log` |
| per-boot environment and its audit | `out/<arm>/env.txt` against `env-expected.txt`, judged by `in/envaudit.py` into `env-diff.txt` |
| planner lines (pool, prompt cache, chunk, vision) | `out/<arm>/plan.txt` and `server.log` |
| depth decode cells | `out/<arm>/conc_L1.json`, `conc_L4.json`, `conc_L8.json`; means, ratios and verdicts by `in/analyze_gaparms.py` |
| round accounting | the engine's own `done ... rounds= accepted=` lines in `out/<arm>/rounds4.log`, cross-checked against the `/metrics` `mtp_*` deltas in `out/<arm>/metrics.txt` |
| client spans a round | `reps[*].client_intervals` in `out/<arm>/conc_L4.json`; the server's `decode=` field where the engine prints one |
| prefill cells | `out/C{3,4}*/ttft_cold.out` summary lines (median seconds, n, excluded) |
| warm turn | `out/W192/ttft_warm.out` summary and sample lines; the planner and cache census in `out/W192/server.log` |
| production's recorded warm reference | `work/DevVsProd/out.fetched/out/P{1,2,3}/ttft.out` (1.254, 1.074 with n 2, 1.041 s; the arm value 1.123 s is their mean) |
| vision | `out/W192/vision.json`, `vision.tail.log`, `vision.log` |
| restore | `out/run.log` (`PROD-BOOT`, `PROD-IMAGE-OK`, `RUN-DONE`, `EXIT-DONE`), `out/health-restored.json`, `out/restored-container.txt` |
| lever names and readers | the string probes of `/opt/tensorfold/native/bin/tensorfold-native` on both images, production's launcher `~/qwen6-start-prod.sh`, our tree `~/work/int4cf/t/zig/src/platform/environment.zig`, production's source `~/work/refsrc/zig/src/families/flashnext/cuda_native.zig` |
