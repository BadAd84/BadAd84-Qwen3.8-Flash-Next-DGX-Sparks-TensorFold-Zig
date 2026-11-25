# RESULT: `TF_FLASHNEXT_SHARED_DRAFTS=1` against `=0`, clean upstream main (issue #4803)

## Tested head and settings (read these first)

- Image: `tensorfold-qwen38:main-9a38b1f7b`, id `sha256:2533c8a882610a69e376d1ea3d89d4ac03add9b1e8b642de6e770fc0ea1cc7e6`, built from upstream `ashhart/TensorFold` `9a38b1f7b33863507cdea47e88207d8b3bea3f22` with NONE of our patch stack (served binary sha256 `8e04b448aac1bccba6452088278d71328aae8b2813eb1e45fe3228c4ec10e933`).
- Build: Zig `0.17.0`, `Cuda compilation tools, release 13.3, V13.3.73 Build cuda_13.3.r13.3/compiler.38244171_0`, on spark6; build log `out/phase0/build.log`.
- Checkpoint: `nvidia/Qwen3.8-Flash-Next-FP4-Local` revision `b9ce18a6887e18c089fdea8509a33e63429a3300`, main's own ModelOpt checkpoint for one GB10 (`docs/recipes/flash-next-cuda.md:236-241`), 96 GiB, mounted read-only at `/models/qwen38`.
- Arm 0 = `TF_FLASHNEXT_SHARED_DRAFTS=0`; arm 1 = `=1` (the shipped default). Nothing else differs between the arms: no other `TF_`/`TENSORFOLD_` name, same launcher, same flags, same client, same prompts.
- Serve command (both arms): `tensorfold-native serve /models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300 --name Qwen3.8-Flash-Next --host 0.0.0.0 --port 8888 --context 32768 --parallel 8 --prompt-cache-gib 3 --temperature 0`.
- Client: chat completions, `temperature 0`, thinking off, `max_tokens 512`, `ignore_eos true`, `draft true`, `return_token_ids true`. Each pass carries a per-boot nonce in its prompt so every decode pass is cold on the prompt cache; the two arms see byte-identical prompt strings (checked below).
- Fresh server per cell, arms interleaved, one GPU box (spark6, GB10, driver 580.178.04), under `flock ~/work/gpu.lock` with production stopped inside the lock and restored by an EXIT trap.

## Headline

**Token hashes are equal across the arms in all 45 measured replies and in the cached control**: the lever changed no reply (compared by full 64-hex `token_sha256` and by the raw token-id lists; the first divergent token would be named here if there were one). The speed and counter differences below are therefore throughput only, not output.

- Hash check: 45 equal / 0 unequal / 0 missing across the four concurrencies; cached control `compared` (equal 2, unequal 0, missing 0).

## The concurrency table (both arms' decode and TTFT, and the S1/S0 ratios)

| C | S0 decode tok/s (agg) | S1 decode tok/s (agg) | S1/S0 | S0 per-stream tok/s | S1 per-stream tok/s | S1/S0 | S0 TTFT s | S1 TTFT s | S1/S0 | hash eq/une/miss |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 48.58 | 44.36 | 0.91 | 48.58 | 44.36 | 0.91 | 0.153 | 0.178 | 1.16 | 3/0/0 |
| 2 | 68.60 | 70.47 | 1.03 | 44.91 | 44.95 | 1.00 | 0.228 | 0.225 | 0.99 | 6/0/0 |
| 4 | 102.81 | 98.93 | 0.96 | 32.79 | 31.88 | 0.97 | 0.385 | 0.379 | 0.98 | 12/0/0 |
| 8 | 136.14 | 139.08 | 1.02 | 23.21 | 23.60 | 1.02 | 0.687 | 0.677 | 0.99 | 24/0/0 |

Note: decode is per-request tokens/round x rounds/s; S1/S0 above 1 means arm 1 (shared drafts ON) is faster at that concurrency, below 1 means slower.

### Noise, the null control, and how to read these ratios

- Pass-to-pass spread of the aggregate decode rate (max/min - 1), arm 0 / arm 1: c1 1.16/0.77, c2 0.17/0.21, c4 0.09/0.12, c8 0.32/0.28. The window's noise rule re-boots both arms of a level once when its three passes span more than 5 percent; all four levels were re-booted once and remained above it, so every level here carries its spread and is read as noisy, not as a fixed number. The level-1 spread is the largest.
- At C=1 there is only one stream per reply, so the shared rule never engages and the two arms run the same code path: c1 is the null control, and any c1 difference is measurement noise. Its wide spread comes from the third pass's prompt, which drafts far worse on BOTH arms (tokens/round 1.59 against 2.6, 322 rounds against ~200), a property of the prompt, not of the lever.
- At C=2, 4 and 8 the lever is reachable (a shared round exists) and it does reach the path: arm 1 drafts fewer tokens a round than arm 0 (ratios 0.87, 0.88, 0.86), which is the shared stop at 0.6 truncating the greedy chain beside another open stream.
- Net effect on throughput: the S1/S0 aggregate ratios are 0.91, 1.03, 0.96, 1.02 at C=1, 2, 4, 8, all inside the measured pass spread. On this checkpoint and this build the lever does not reproduce a 7 to 11 percent speed-up at any concurrency tested; the first-pass figures (which showed up to +8 percent) came from single-pass noise and the re-boot removed them.

## The draft and acceptance counters

How this engine exposes them (three independent surfaces, all read by the harness):
- `/metrics`, Prometheus text: `tensorfold:mtp_drafted_total` "Draft tokens verified on finished requests", `tensorfold:mtp_accepted_total` "Draft tokens kept on finished requests", `tensorfold:decode_rounds_total` (`zig/src/server/metrics.zig:141-149`).
- Per reply, the `tensorfold.speculative` object: `rounds`, `drafted`, `accepted`, `acceptance_rate`, `tokens_per_round` (`zig/src/server/chat_generation.zig:435-441`).
- The server's own log, one `done` line per request: `rounds=<r> accepted=<a>/<d>` (`zig/src/server/chat_generation.zig:484`).

| C | drafted/round S0 | drafted/round S1 | S1/S0 | accepted/round S0 | accepted/round S1 | accept rate S0 | accept rate S1 | S0 drafted (metrics delta) | S0 accepted (metrics delta) | S1 drafted (metrics delta) | S1 accepted (metrics delta) |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 3.02 | 3.02 | 1.01 | 1.53 | 1.53 | 0.343 | 0.341 | 2913 | 1143 | 2391 | 818 |
| 2 | 3.95 | 3.42 | 0.93 | 2.13 | 1.98 | 0.550 | 0.578 | 3813 | 2096 | 3580 | 2068 |
| 4 | 3.74 | 3.29 | 0.92 | 2.37 | 2.20 | 0.641 | 0.678 | 6841 | 4387 | 6328 | 4286 |
| 8 | 3.74 | 3.23 | 0.91 | 2.24 | 2.07 | 0.615 | 0.658 | 13880 | 8530 | 12616 | 8305 |

`drafted/round`, `accepted/round` and the accept rate are medians over the three passes of the reply's own `tensorfold.speculative` block (per-reply counters, summed per pass). The metrics-delta columns are the `/metrics` counter difference across a pass. The two disagree on 13 of the 48 decode passes (7 on arm 0, 6 on arm 1), by 2 to 539 tokens; every disagreement is the previous pass's last reply completing just after that pass's `before` scrape (largest on the third pass: 539 on arm 0 c1, 447 on arm 1 c1). The ratios use the reply-summed counters, which are self-contained per reply and identical in structure on both arms.

## The cached two-stream control (separately)

Prime each of two prompts alone (one 512-token stream each), then send both together and read the cached-token counts, TTFT and the counters.

| arm | prompt tokens (s1/s2) | cached tokens (s1/s2) | cache state | TTFT s (s1/s2) | server TTFT s | decode tok/s (s1/s2) | drafted | accepted | metrics cached delta |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 0 | [56, 54] | [49, 47] | ['reused', 'reused'] | [0.1393, 0.0616] | [0.138, 0.0606] | [38.73, 67.54] | 2639 | 1527 | 100 |
| 1 | [56, 54] | [49, 47] | ['reused', 'reused'] | [0.1383, 0.0617] | [0.1372, 0.0607] | [40.46, 70.56] | 2581 | 1517 | 100 |

- Cached-control token hashes across arms: `compared` (equal 2, unequal 0, missing 0; prompts 2 of 2 equal).

## Restore proof

- `[2026-11-24T22:07:29+00:00] RESTORED health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f envcheck rc 0 :: prod-env: 117 rows compared (54 carried, 63 pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)`
- restored image/cmd: `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`
- `/health`: `{"status": "ok", "model": "Qwen3.8-Flash-Next", "model_ids": ["Qwen3.8-Flash-Next"], "max_batch_size": 8, "warming": false, "memory": {}, "live": {"connections": 1, "waiting": 0, "decode_tokens_per_se`
- `prod-env: 117 rows compared (54 carried, 63 pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)`

## Tables (verbatim from the window's `tables.md`)

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

## Evidence bundle

Raw evidence under `docs/receipts/SharedDraftsMain/evidence/`: `score.json`, `score1.txt`, `score2.txt`, `tables.md`, `run.log`, and per cell `out/arm<A>/<cell>/` (`cell.json` with every reply's full `token_sha256`, token ids, TTFT, decode rate, `speculative` counters and usage; `metrics-*.txt` the `/metrics` scrapes; `inspect-boot.json`, `cmd-boot.json`, `env-boot.txt`, `server-log-boot.txt`, `server-log-end.txt` with the engine's own `done` lines; `gpu.txt` thermals), plus `out/phase0/` (build log, checkpoint hashes) and `out/restored/` (restore proof).

## Limits and deviations

- One checkpoint (main's own ModelOpt FP4-Local, not the dev stack's INT4-AutoRound), one box, one window, one build; the checkpoint choice is main's own documented one for one GB10, stated because the request names the dev-stack checkpoint as what is being replaced.
- The prompt cache is on (3 GiB) because the cached control needs it; every decode pass is made cold by its per-boot nonce and the idle cases are checked to read `cached_tokens = 0`.
- The lever's reader is `zig/src/families/flashnext/cuda_lanes_draft.zig:45-48`; arm 1 beside another open stream stops a greedy chain at `shared_stop = 0.6` (:32), arm 0 keeps the engine rule (`TF_FLASHNEXT_CONFIDENCE` default -0.4). Both arms keep their defaults for chain depth (6, greedy 8) and wide (4).

