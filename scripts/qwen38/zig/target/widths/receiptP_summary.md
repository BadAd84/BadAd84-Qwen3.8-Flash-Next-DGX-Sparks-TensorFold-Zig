# Widths cold-prompt receipt (#3368 step 1): images wm (main 2ba55ec7d3) and wb (main plus the widths patch), --prompt-cache-gib 0, spark6, 2026-11-15

START 2026-11-15T06:51:28+00:00
IMAGE wm e971c21a08f5
IMAGE wb 2753b07e7e0c
=== M1 2026-11-15T06:52:04+00:00 boot rc 0 gpu 53,2405MHz
=== B1 2026-11-15T06:55:35+00:00 boot rc 0 gpu 60,2411MHz
=== B2 2026-11-15T06:59:04+00:00 boot rc 0 gpu 63,2437MHz
=== M2 2026-11-15T07:02:35+00:00 boot rc 0 gpu 63,2450MHz
ARMS DONE 2026-11-15T07:05:32+00:00
RESTORE prod /health 200 2026-11-15T07:07:00+00:00

| prompt | M1 | B1 | B2 | M2 | branch against main | slower? |
|---|---|---|---|---|---|---|
| cold 2k, ttft.py median of 3 (s) | 1.069 | 1.051 | 1.082 | 1.073 | -0.42% | no slower |
| cold 8k, ttft.py median of 3 (s) | 4.038 | 3.983 | 4.017 | 4.005 | -0.53% | no slower |
| cold 32k, ttft.py median of 3 (s) | 16.054 | 15.925 | 16.153 | 16.066 | -0.13% | no slower |
| cold 64k, ttft.py median of 3 (s) | 33.060 | 32.828 | 33.156 | 33.098 | -0.26% | no slower |
| bench_cache --require-cold, 2571 tokens, first ttft_s | 1.225 | 1.223 | 1.226 | 1.227 | -0.12% | no slower |

cached tokens on each cold first request: M1 0 B1 0 B2 0 M2 0
