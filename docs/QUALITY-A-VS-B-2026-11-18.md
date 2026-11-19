# Quality: INT4-AutoRound against FP4-Local, one window (spark6, 2026-11-19)

STATUS: measured 2026-11-19, 02:07 to 06:11 UTC, one window inside the GPU lock. Both arms ran the same
1,664 request bodies; production was restored and answers `/health` 200.

## What was compared

| arm | checkpoint | served by | image |
|---|---|---|---|
| A | `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` @ `1464274120d36a4d8fcaa934552334a7d83ce0fd` (GPTQ int4 experts, 5 routed a token, shared expert 1280) | production's own serve, `~/qwen6-start-prod.sh` | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, id `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`, created 2026-10-14, `tf.kernels=present`, `tf.patches=4144696f21e3`, `ai-engine.src-sha256=e5139fcd8c6101c7` |
| B | `nvidia/Qwen3.8-Flash-Next-FP4-Local` @ `b9ce18a6887e18c089fdea8509a33e63429a3300` (NVFP4 experts, MXFP8 projections, 10 routed a token, shared expert 640) | our recipe's Zig serve, `~/work/lanes/rpr/recipe/start.sh` with `CHECKPOINT=nvfp4` | `tensorfold-qwen38:t5-b-c0eb2126`, id `sha256:6cddc095865c742faedb0c35aa46f9c8ec187f8f7b8b74705b6e7e84a70c2096`, created 2026-11-17, `tf.kernels=embedded`, `tf.patches=4144696f21e3` |

A's boot banner: `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window ·
fp8 KV · vision on · drafts MTP · port 8888` (production recipe `~/qwen-zig-prod` at
`364f21a1a46a366fa39c4da0d53b7b1f38624610`, 1.0.0). B's: `nvidia/Qwen3.8-Flash-Next-FP4-Local · 4 at once ·
131072-token window · bf16 KV · vision off · drafts MTP · port 8888`, and its engine line: `model 72.73 GiB;
4 streams at once, 4.11 GiB each at a 131072-token window, of 27.8 GiB left after a 9.0 GiB reserve; prompts
in passes of up to 1536 rows, a 11.3 GiB prompt cache; own glue kernels` (`/health` version 1.2.9, backend
cuda, device NVIDIA GB10). B's image refuses fp8 KV (`tensorfold: --kv-cache fp8: this CUDA family keeps
bf16 caches; serve without it`), so B ran bf16 KV where A ran fp8. Both serves report model id
`Qwen3.8-Flash-Next`.

Only one model fits the Spark, so the arms ran back to back inside one GPU lock (A 02:09 to 03:40, B 03:41 to
06:09, restore 06:11).

## Method

- **Greedy, no sampling**: `temperature: 0`, no seed, no top-p/top-k; `max_tokens` per benchmark (GSM8K 1024,
  MMLU-Pro 1536, HumanEval 1024) and `stop` fixed in the prompt files.
- **Byte-identical requests**: the prompts were rendered ONCE on the laptop from the checkpoint's own chat
  template (`chat_template.jinja`, sha256 `c3cf9e34abf4f9e36c2d72165aa9c132d3e2a725b6c2586aaa3a8af9d7a81041`,
  the same file in both checkpoints) with `enable_thinking: false`, then sent verbatim to
  `/v1/completions`, so no server-side template ran. The saved records confirm the equality: **1,664 of
  1,664 items have the same `prompt_sha256` and the same `body_sha256` in both arms**, including the `model`
  field. HumanEval uses the canonical raw completion prompt.
- **Thinking off, proved on both arms**: the chat probe with `chat_template_kwargs {"enable_thinking": false}`
  answered `4` with an empty `reasoning_content` and no think block, and each arm's first benchmark completion
  contains no `<think>` (`out/<arm>/thinking_probe.json`). B was also booted with `THINKING=0`.
- **Concurrency 4** for both arms, so equal request pressure. A serves 8 slots, B was booted with
  `PARALLEL=4` (four full 131,072-token windows fit its 27.8 GiB pool). The client streamed, recorded TTFT,
  per-request decode tok/s, completion tokens and `finish_reason`, and was resumable by item id.
- **Datasets** (official, pinned; prompts hash-checked on the box against the manifest:
  GSM8K `3fc07867...`, MMLU-Pro `d24100ce...`, HumanEval `d1644fe7...`):
  - GSM8K `openai/gsm8k` @ `740312add88f781978c0658806c59bc2815b9866`, 500 of 1,319 test problems by
    `random.Random(20261118).sample` over question-sorted indices; 8-shot chain of thought with train
    examples 0-7; number after the last `####`, else the last number; numeric compare.
  - MMLU-Pro `TIGER-Lab/MMLU-Pro` @ `b189ec765aa7ed75c8acfea42df31fdae71f97be`, 1,000 of 12,032 test
    questions stratified over the 14 categories (proportional largest-remainder, same seed); zero-shot chain
    of thought, final line `The answer is X`; last `answer is X`, else the last standalone A-J letter.
  - HumanEval `openai/openai_humaneval` @ `7dce6050a7d6d172f3cc5c32aa97f52fa1a2e544`, all 164 problems,
    canonical prompt and stops; pass@1 by executing the official test code in a subprocess (`python -I`,
    15 s timeout) on the laptop.
- **Numbers**: accuracy per arm with a 95% Wilson interval; the paired difference on the same items with the
  exact McNemar test on discordant pairs; only-A and only-B counts; truncations (`finish_reason == "length"`);
  mean completion tokens; mean per-request decode tok/s; and a completed-reply sensitivity (replies the serve
  stopped itself) for the truncated benchmark.
- **Scoring is offline** from the saved JSONL (`scripts/quality/quality_score.py`), so every cell re-derives
  from raw replies without the GPU.

## Results, all items

| bench | items | paired | A acc (95% Wilson) | B acc (95% Wilson) | diff pp (B-A) | only A | only B | McNemar p | trunc A/B | mean tok A/B | decode tok/s A/B |
|---|---|---|---|---|---|---|---|---|---|---|---|
| GSM8K | 500 | 500 | 482/500 = 96.4% [94.4, 97.7] | 484/500 = 96.8% [94.9, 98.0] | +0.4 | 3 | 5 | 0.727 | 3/2 | 146.5/145.6 | 39.19/25.28 |
| MMLU-Pro | 1000 | 1000 | 759/1000 = 75.9% [73.2, 78.5] | 752/1000 = 75.2% [72.4, 77.8] | -0.7 | 53 | 46 | 0.547 | 203/203 | 897.2/912.7 | 48.88/30.39 |
| HumanEval | 164 | 164 | 133/164 = 81.1% [74.4, 86.4] | 143/164 = 87.2% [81.2, 91.5] | +6.1 | 7 | 17 | 0.064 | 7/3 | 105.3/86.1 | 45.65/28.17 |

Missing replies: 0 in both arms, every benchmark. Replies the extractor could not turn into an answer at all
(no number or no A-J letter anywhere): GSM8K 0/0, MMLU-Pro 104/121, HumanEval not applicable. All MMLU-Pro
misses are truncated replies (see below), not format misses: among replies the serve finished itself there
were 0 extraction failures.

## Results, completed replies only (finish_reason not "length")

| bench | A acc (95% Wilson) | B acc (95% Wilson) | paired | only A | only B | diff pp (B-A) | McNemar p |
|---|---|---|---|---|---|---|---|
| GSM8K | 482/497 = 97.0% [95.1, 98.2] | 483/498 = 97.0% [95.1, 98.2] | 496 | 3 | 5 | +0.4 | 0.727 |
| MMLU-Pro | 733/797 = 92.0% [89.9, 93.7] | 732/797 = 91.8% [89.7, 93.5] | 750 | 12 | 7 | -0.7 | 0.359 |
| HumanEval | 133/157 = 84.7% [78.3, 89.5] | 143/161 = 88.8% [83.0, 92.8] | 154 | 4 | 12 | +5.2 | 0.077 |

## Interpretation

- **GSM8K: indistinguishable.** 96.4% against 96.8%, a +0.4 pp difference with p = 0.727, and the
  completed-reply view is 97.0% against 97.0%. At this level the benchmark is near its ceiling for both
  conversions.
- **MMLU-Pro: indistinguishable, with a protocol defect.** 75.9% against 75.2% (p = 0.547), and on the
  replies the serve finished, 92.0% against 91.8% (p = 0.359). 203 of 1,000 replies in EACH arm hit the
  1,536-token cap before writing a final line, so the all-items numbers carry the same 20.3% penalty on both
  sides and are a lower bound, not a fair absolute score. The cap was too small for this zero-shot chain of
  thought prompt; a future run should use 3,072 tokens. The completed-reply comparison is the fair one and
  says the two models answer the questions they finish equally well.
- **HumanEval: B ahead, not significant.** B passes 143 of 164 against 133 (87.2% against 81.1%), +6.1 pp,
  p = 0.064; on completed replies +5.2 pp, p = 0.077. B wins 17 items A loses against 7 the other way. With
  164 problems this is a direction, not a result: the 95% intervals overlap and the paired test does not
  reach 0.05. The direction is consistent in the completed-reply view, which is all this sample can say.
- **No benchmark shows A ahead by a meaningful margin.** The two checkpoints serve at statistically
  indistinguishable quality on GSM8K and MMLU-Pro, and B has a small, unconfirmed HumanEval edge.
- **Side line, speed.** At concurrency 4 the mean per-request decode rates were A 39.2 / 48.9 / 45.7 tok/s
  and B 25.3 / 30.4 / 28.2 (GSM8K / MMLU-Pro / HumanEval). That is not a quality measure: the engines and
  slot counts differ (A 8 slots, B 4) and it is not a like-for-like speed comparison, which belongs to the
  speed campaign.

## What the numbers do and do not establish

- **This is a model comparison, not an ablation of the expert count.** The checkpoints differ in routed
  experts (5 against 10 a token), expert format (GPTQ int4 against NVFP4), shared-expert width (1280 against
  640) and everything else the two conversions changed (calibration, quantisation-aware distillation for the
  FP4 checkpoint). Nothing here isolates the expert count or the numeric format.
- **The engines differ.** A runs production's 1.0.0 image with its zmerge8 knob set; B runs a newer recipe
  image (same recipe patch hash `4144696f21e3`, different source tree and environment, engine version 1.2.9).
  Kernel-level numeric differences could flip a greedy tie; neither arm was proved bit-identical to a stock
  engine in this window.
- **KV cache precision differs.** A ran fp8 KV (lossy, about 98.8% top-1 agreement with bf16 in the recipe's
  own note); B's image refuses fp8 and ran bf16. If anything this favours A on quality, and A shows no
  significant advantage on any benchmark here.
- **Drafts are on in both arms.** The recipe verifies drafts before acceptance, and the campaign's exactness
  receipts (golden 6/6 identical replies across levers, `docs/CATCHUP-1.2.6.md`; the recipe's "drafts are
  checked, so replies match serial decoding") establish that drafting changes speed, not tokens. This window
  did not re-prove drafts-on against drafts-off.
- **One run, greedy, no repeats.** The Wilson intervals describe uncertainty over the sampled items, not
  run-to-run variation. Greedy decoding makes a rerun deterministic on the same engine.
- **Contamination is possible.** All three benchmarks are public and neither checkpoint's training data is
  audited here; contamination inflates both arms and need not inflate them equally.
- **MMLU-Pro is zero-shot here** (published numbers are 5-shot chain of thought), so absolutes are not
  leaderboard comparable, only comparable to each other. **The 1,536-token cap truncated 20.3% of MMLU-Pro
  replies in both arms**; the all-items figure is a lower bound and the completed-reply table is the fair
  comparison for that benchmark.
- **HumanEval**: one greedy sample a problem, executed on the laptop in a subprocess with a 15 s timeout, no
  network isolation and no memory cap; not the unbiased pass@1 estimator over k samples.
- **Decode tok/s** is per request at client concurrency 4 on differently sized serves, so it is not a
  single-stream or like-for-like speed number.

## Provenance and exact commands

- Prompt build (laptop): `python scripts/quality/quality_build_prompts.py`; dataset revisions and file
  hashes in `work/QualityCmp/data/manifest.json`; prompts copied to spark6 and hash-checked there in both
  arms' `provenance.txt`.
- Window launch (spark6, inside the lock):
  `setsid nohup flock -o -w 43200 /home/adam/work/gpu.lock bash /home/adam/work/qualitycmp/quality_run_window.sh ...`;
  every step timestamped in `work/QualityCmp/out/driver.log` (`A boot rc 0` 02:09:07, `A full run done`
  03:40:20, `B boot OK image=t5-b-c0eb2126 kv=bf16` 03:41:15, `B full run done` 06:09:26, `RESTORE done`
  06:11:04).
- Scoring (laptop): `python scripts/quality/quality_score.py --arms A,B --benches gsm8k,mmlupro,humaneval
  --raw work/QualityCmp/raw --out work/QualityCmp/scores`; `scores/summary.json` carries every per-item
  outcome.
- Hashes of the exact files run: client `6853ccf90748d39b71084341a9c73a20290e9d30d504db3a256db2a284cca2b6`,
  thinking probe `02887beacfeb44a934576d08b22242b066416faca86d23dcb91adf82ea6a329b`, window driver
  `8cbc79b6bf993dca31c9c78b2e55fd3aac8a12e0c8678bed2f58ea051241aa35`, scorer
  `9b583cce3284e0907518d27b7d97c00aa90bc9434c67ae5263289767be34ca7a`. Prompt files `3fc07867...`, `d24100ce...`, `d1644fe7...`; chat template `c3cf9e34...`.
- Both serves' `/v1/models` id: `Qwen3.8-Flash-Next`. The stop-field probe was accepted by both
  (`PROBE stop http=200`).
- Restore: `RESTORE health 200 models Qwen3.8-Flash-Next`; `final_docker_ps.txt` reads
  `qwen38-flash-next-tf | tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 | Up About a minute`; the live
  `/health` body is
  `{"status": "ok", "model": "Qwen3.8-Flash-Next", "model_ids": ["Qwen3.8-Flash-Next"], "max_batch_size": 8, "warming": false, "memory": {}, "live": {"connections": 0, "waiting": 0, "decode_tokens_per_second": 1.0, "prefill_tokens_per_second": 243.7}}`.

## Restore

`( cd ~/work/lanes/rpr/recipe && ./stop.sh ); ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null )`; the
window ended on `/health` 200 with production's image running, quoted above.
