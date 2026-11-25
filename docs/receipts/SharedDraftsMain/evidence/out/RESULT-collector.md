# RESULT: TF_FLASHNEXT_SHARED_DRAFTS=1 against =0 on a clean upstream main (issue #4803)

Image `tensorfold-qwen38:main-9a38b1f7b` (sha256:2533c8a882610a69e376d1ea3d89d4ac03add9b1e8b642de6e770fc0ea1cc7e6), built from `ashhart/TensorFold` `9a38b1f7b33863507cdea47e88207d8b3bea3f22` with no OTS patch stack (binary sha256 `8e04b448aac1bccba6452088278d71328aae8b2813eb1e45fe3228c4ec10e933`). Checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` at `b9ce18a6887e18c089fdea8509a33e63429a3300`, main's own ModelOpt checkpoint for one GB10. Arm 0 `TF_FLASHNEXT_SHARED_DRAFTS=0`, arm 1 `=1`; everything else equal and captured per boot.

## Headline

Token hashes are equal across the arms in all 45 measured replies and in the cached control: the lever changed no reply. The speed and counter differences are in the tables below.

| C | arm0 aggregate tok/s | arm1 aggregate tok/s | arm1/arm0 | TTFT arm0 s | TTFT arm1 s | hash equal/unequal/missing |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 48.58 | 44.36 | 0.91 (-8.69%) | 0.153 | 0.178 | 3/0/0 |
| 2 | 68.60 | 70.47 | 1.03 (2.73%) | 0.228 | 0.225 | 6/0/0 |
| 4 | 102.81 | 98.93 | 0.96 (-3.78%) | 0.385 | 0.379 | 12/0/0 |
| 8 | 136.14 | 139.08 | 1.02 (2.16%) | 0.687 | 0.677 | 24/0/0 |

## Draft and acceptance counters (per decode round, medians of the three passes)

| C | drafted/round a0 | drafted/round a1 | accepted/round a0 | accepted/round a1 | accept rate a0 | accept rate a1 | tokens/round a0 | tokens/round a1 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 3.02 | 3.02 | 1.53 | 1.53 | 0.343 | 0.341 | 2.53 | 2.53 |
| 2 | 3.95 | 3.42 | 2.13 | 1.98 | 0.550 | 0.578 | 3.13 | 2.99 |
| 4 | 3.74 | 3.29 | 2.37 | 2.20 | 0.641 | 0.678 | 3.37 | 3.21 |
| 8 | 3.74 | 3.23 | 2.24 | 2.07 | 0.615 | 0.658 | 3.25 | 3.07 |

## Cached two-stream control

| arm | prompt tokens (stream 1 / stream 2) | cached tokens (stream 1 / stream 2) | TTFT s | decode tok/s (stream 1 / stream 2) | drafted | accepted |
| --- | --- | --- | --- | --- | --- | --- |
| 0 | [56, 54] | [49, 47] | [0.1392914500029292, 0.061627578994375654] | [38.7343584194956, 67.54395190562792] | 2639.0 | 1527.0 |
| 1 | [56, 54] | [49, 47] | [0.13828381401253864, 0.06167460000142455] | [40.45567559441951, 70.55849775685785] | 2581.0 | 1517.0 |

Cached-control token hashes across the arms: compared (equal 2, unequal 0, missing 0; prompts equal 2 of 2).

## Restore proof

- `[2026-11-24T22:07:29+00:00] RESTORED health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f envcheck rc 0 :: prod-env: 117 rows compared (54 carried, 63 pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)`
- restored image: `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`
- `/health` body: `{"status": "ok", "model": "Qwen3.8-Flash-Next", "model_ids": ["Qwen3.8-Flash-Next"], "max_batch_size": 8, "warming": fal`
- `prod-env: 117 rows compared (54 carried, 63 pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)`

## Evidence bundle

Per cell: `out/arm<A>/<cell>/cell.json` (every reply's `token_sha256`, token ids, TTFT, decode rate, `speculative` counters, usage), `metrics-*.txt` (the `/metrics` scrapes the counter deltas come from), `inspect-boot.json`, `cmd-boot.json`, `env-boot.txt`, `server-log-boot.txt` and `server-log-end.txt` (the engine's own `done ... rounds= accepted=/drafted=` lines), `gpu.txt` (thermals). The whole `out/` tree is in `out-bundle.tgz`.

## Tables (verbatim from tables.md)

# Clean-main TF_FLASHNEXT_SHARED_DRAFTS window: TF_FLASHNEXT_SHARED_DRAFTS=1 against =0

Arm 0: `TF_FLASHNEXT_SHARED_DRAFTS=0`; arm 1: `TF_FLASHNEXT_SHARED_DRAFTS=1` (engine default).
Same image, checkpoint, launcher, serve flags, client and prompts; fresh server per cell.

## Decode by client concurrency (3 cold passes a cell, medians)
| C | arm | aggregate tok/s | spread | per-stream tok/s (median, min-max) | TTFT s median | TTFT s max | server TTFT s | prefill s | idle 1k TTFT s | idle 8k TTFT s | tokens/round | drafted/round | accepted/round | drafted | accepted | accept rate | rounds | metrics drafted | metrics accepted | failed |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0 | 48.58 | 1.16 | 48.58 (23.95-51.79) | 0.15 | 0.15 | 0.15 | 0.15 | 0.54 | 3.28 | 2.53 | 3.02 | 1.53 | 2374 | 815 | 0.34 | 719 | 2913.00 | 1143.00 | 0 |
| 1 | 1 | 44.36 | 0.77 | 44.36 (28.36-50.32) | 0.18 | 0.18 | 0.18 | 0.18 | 0.54 | 3.28 | 2.53 | 3.02 | 1.53 | 2387 | 815 | 0.34 | 719 | 2391.00 | 818.00 | 0 |
| 2 | 0 | 68.60 | 0.17 | 44.91 (32.67-53.92) | 0.23 | 0.32 | 0.23 | 0.23 | 0.55 | 3.30 | 3.13 | 3.95 | 2.13 | 3813 | 2096 | 0.55 | 971 | 3813.00 | 2096.00 | 0 |
| 2 | 1 | 70.47 | 0.21 | 44.95 (32.18-53.45) | 0.22 | 0.30 | 0.22 | 0.15 | 0.54 | 3.37 | 2.99 | 3.42 | 1.98 | 3538 | 2046 | 0.58 | 1021 | 3580.00 | 2068.00 | 0 |
| 4 | 0 | 102.81 | 0.09 | 32.79 (24.76-56.05) | 0.38 | 0.63 | 0.38 | 0.30 | 0.54 | 3.29 | 3.37 | 3.74 | 2.37 | 6809 | 4364 | 0.64 | 1770 | 6841.00 | 4387.00 | 0 |
| 4 | 1 | 98.93 | 0.12 | 31.88 (24.02-53.78) | 0.38 | 0.65 | 0.38 | 0.23 | 0.54 | 3.26 | 3.21 | 3.29 | 2.20 | 6288 | 4265 | 0.68 | 1869 | 6328.00 | 4286.00 | 0 |
| 8 | 0 | 136.14 | 0.32 | 23.21 (13.68-32.56) | 0.69 | 1.29 | 0.68 | 0.56 | 0.54 | 3.27 | 3.25 | 3.74 | 2.24 | 13839 | 8508 | 0.61 | 3757 | 13880.00 | 8530.00 | 0 |
| 8 | 1 | 139.08 | 0.28 | 23.60 (14.25-34.00) | 0.68 | 1.29 | 0.68 | 0.56 | 0.55 | 3.29 | 3.07 | 3.23 | 2.07 | 12616 | 8305 | 0.66 | 3960 | 12616.00 | 8305.00 | 0 |

## Ratio arm 1 / arm 0, and the token-hash check
| C | aggregate | aggregate % | per-stream | per-stream % | TTFT | TTFT % | server TTFT | drafted | accepted | rounds | hash equal | hash unequal | hash missing | first divergence |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 0.91 | -8.69 | 0.91 | -8.69 | 1.16 | 15.80 | 1.16 | 1.01 | 1.00 | 1.00 | 3 | 0 | 0 | - |
| 2 | 1.03 | 2.73 | 1.00 | 0.10 | 0.99 | -1.44 | 0.98 | 0.93 | 0.98 | 1.05 | 6 | 0 | 0 | - |
| 4 | 0.96 | -3.78 | 0.97 | -2.78 | 0.98 | -1.61 | 0.98 | 0.92 | 0.98 | 1.06 | 12 | 0 | 0 | - |
| 8 | 1.02 | 2.16 | 1.02 | 1.69 | 0.99 | -1.49 | 0.99 | 0.91 | 0.98 | 1.05 | 24 | 0 | 0 | - |

## Idle TTFT (one stream, server idle, cold prompt, 2 reps a boot, every boot pooled)
| arm | reps | 1k TTFT s median | 1k prompt tokens | 1k cached max | 8k TTFT s median | 8k prompt tokens | 8k cached max | errors |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | 18 | 0.55 | [955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950] | 2 | 3.29 | [7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439] | 2 | [] |
| 1 | 18 | 0.54 | [955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950, 955, 950] | 2 | 3.28 | [7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439, 7438, 7439] | 2 | [] |

## Cached two-stream control (prime each prompt alone, then both streams together)
| arm | two-stream cached tokens | two-stream prompt tokens | cache state | TTFT s | server TTFT s | decode tok/s | drafted | accepted | metrics cached delta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | [49, 47] | [56, 54] | ['reused', 'reused'] | [0.1392914500029292, 0.061627578994375654] | [0.138033034, 0.060587771] | [38.7343584194956, 67.54395190562792] | 2639.00 | 1527.00 | 100.00 |
| 1 | [49, 47] | [56, 54] | ['reused', 'reused'] | [0.13828381401253864, 0.06167460000142455] | [0.137212472, 0.060685498] | [40.45567559441951, 70.55849775685785] | 2581.00 | 1517.00 | 100.00 |

Cached-control token hashes across arms: compared (equal 2, unequal 0, missing 0; prompts equal 2 of 2).

## Arm environment identity (the container's TF_/TENSORFOLD_ names, per cell)
- c1: differs; only arm0 ['TF_FLASHNEXT_SHARED_DRAFTS=0']; only arm1 ['TF_FLASHNEXT_SHARED_DRAFTS=1']
- c2: differs; only arm0 ['TF_FLASHNEXT_SHARED_DRAFTS=0']; only arm1 ['TF_FLASHNEXT_SHARED_DRAFTS=1']
- c4: differs; only arm0 ['TF_FLASHNEXT_SHARED_DRAFTS=0']; only arm1 ['TF_FLASHNEXT_SHARED_DRAFTS=1']
- c8: differs; only arm0 ['TF_FLASHNEXT_SHARED_DRAFTS=0']; only arm1 ['TF_FLASHNEXT_SHARED_DRAFTS=1']
- cached: differs; only arm0 ['TF_FLASHNEXT_SHARED_DRAFTS=0']; only arm1 ['TF_FLASHNEXT_SHARED_DRAFTS=1']
- c1 command: same ["serve","/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300","--name","Qwen3.8-Flash-Next","--host","0.0.0.0","--port","8888","--context","32768","--parallel","8","--prompt-cache-gib","3","--temperature","0"]
- c2 command: same ["serve","/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300","--name","Qwen3.8-Flash-Next","--host","0.0.0.0","--port","8888","--context","32768","--parallel","8","--prompt-cache-gib","3","--temperature","0"]
- c4 command: same ["serve","/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300","--name","Qwen3.8-Flash-Next","--host","0.0.0.0","--port","8888","--context","32768","--parallel","8","--prompt-cache-gib","3","--temperature","0"]
- c8 command: same ["serve","/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300","--name","Qwen3.8-Flash-Next","--host","0.0.0.0","--port","8888","--context","32768","--parallel","8","--prompt-cache-gib","3","--temperature","0"]
- image ids across the 18 captured cells: ['tensorfold-qwen38:main-9a38b1f7b sha256:2533c8a882610a69e376d1ea3d89d4ac03add9b1e8b642de6e770fc0ea1cc7e6']
- speculative counters with accepted > drafted: none

Noise rule: a level whose three passes span more than 5 percent is re-booted once for both arms. Final rerun levels: []

Rendered prompt tokens (same prompt strings must render to the same count on both arms): c1: 3 equal / 0 unequal; c2: 6 equal / 0 unequal; c4: 12 equal / 0 unequal; c8: 24 equal / 0 unequal
Lever signature (a shared round must draft fewer tokens a round on arm 1; c1 has no shared round, so it is the null control): c2: drafted/round arm1/arm0 0.867, lever reached the path: yes; c4: drafted/round arm1/arm0 0.880, lever reached the path: yes; c8: drafted/round arm1/arm0 0.863, lever reached the path: yes

