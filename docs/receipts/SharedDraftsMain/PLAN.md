# PLAN for issue #4803: TF_FLASHNEXT_SHARED_DRAFTS=1 against =0 on a clean upstream main

Status: written before the first boot of this window. All paths are on spark6 unless said otherwise.
Owner of the worktree: this session (`work/SharedDraftsMain/`); no repository commits, no public text.

## 1. What the maintainer asked for (verbatim, issue #4803)

> Your numbers come from the patched stack, so they don't yet show the same 7 to 11 percent on main with a
> different checkpoint and confidence. The useful next step is one build with TF_FLASHNEXT_SHARED_DRAFTS=1
> against =0, on a checkpoint main serves directly, with fresh servers at several concurrencies, draft and
> acceptance counters, and full token hashes. Please include the cached two-stream control before we consider
> changing the default.

## 2. Image: a clean build of upstream main, no OTS patch stack, no lever beyond the one under test

- Upstream repository: `ashhart/TensorFold` (https://github.com/ashhart/TensorFold).
- Commit built: `9a38b1f7b33863507cdea47e88207d8b3bea3f22` (`9a38b1f7b`, main's tip when fetched
  2026-11-24; `git log -1` subject "changelog: #4110 under Unreleased"). Tree
  `6e00d270fec84cb6decb784e148712d4d27b5f03`.
- Source: `git archive --format=tar.gz --prefix=src/ 9a38b1f7b`, sha256
  `7b91b872d4d0e78d4ecc27be8b5c947477225da607cece56a8e911e9abad5297`, 44,952,663 bytes. Nothing is
  applied on top: the archive is the tree, no `patches/`, no OTS env.
- Dockerfile: `work/SharedDraftsMain/Dockerfile` (copied to spark6 `~/work/SharedDraftsMain/build/Dockerfile`).
  Build steps are main's own receipt steps (`docs/receipts/flashnext-prompt-chunk3072/README.md:9`):
  `zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold -j$(nproc) fatbins install native`.
- Zig: `0.17.0` (upstream `.zig-version` says `0.17.0`; `.github/workflows/zig-fmt.yml:32` pins `version: 0.17.0`).
  Tarball `zig-aarch64-linux-0.17.0.tar.xz`, sha256
  `9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8` (the pin used by every image on this box),
  checked in the Dockerfile with `sha256sum -c`.
- nvcc: CUDA 13.3, V13.3.73 (`Build cuda_13.3.r13.3/compiler.38244171_0`), from
  `nvcr.io/nvidia/pytorch:26.07-py3` (image id `15b8de8baabe` locally). The build log quotes it again.
- Image tag: `tensorfold-qwen38:main-9a38b1f7b`. Build log: `~/work/SharedDraftsMain/build/build.log` on
  spark6 (its first lines carry the source sha, tarball hash, Zig version, nvcc version; the last line the
  image id and the binary's sha256). Built on spark6 (CPU only; no GPU lock needed; spark6 is the only GPU box).
- The served binary is the build's own: `sha256sum /opt/tensorfold/native/bin/tensorfold-native` is printed by
  the build and re-read from the image at preflight.

## 3. Checkpoint: the one main's own docs and receipts serve on one GB10

Choice: `nvidia/Qwen3.8-Flash-Next-FP4-Local` at revision `b9ce18a6887e18c089fdea8509a33e63429a3300`.

Evidence in upstream main's own tree:

- `docs/recipes/flash-next-cuda.md:236` heading "The ModelOpt checkpoint on one GB10"; `:238` names
  `nvidia/Qwen3.8-Flash-Next-FP4-Local` (revision `b9ce18a6`) on a GB10 (128 GB, driver 580.178, CUDA 13.3),
  greedy, `--prompt-cache-gib 0` for that measurement, `:239`-`:241` describe the runs.
- `docs/hermes-agent.md:51`: "On a DGX Spark (GB10) with TensorFold 1.2.3 serving
  `nvidia/Qwen3.8-Flash-Next-FP4-Local` (`--context 131072 --parallel 2 --dashboard`)" - main serving this
  checkpoint on one GB10, with concurrency.
- Full revision, main's own receipts: `docs/receipts/flashnext-draft-head/README.md:19` and
  `docs/receipts/flashnext-readout-fused/README.md:19` and `docs/receipts/flashnext-prompt-chunk3072/README.md:9`
  all pin revision `b9ce18a6887e18c089fdea8509a33e63429a3300`.
- The alternative main documents first, `TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP`
  (`docs/recipes/flash-next-cuda.md:86-87`), is NOT used: it is a 105.5 GiB download
  (`docs/supported-models.md:36`) and spark6 holds 116 GiB free on `/home` (measured `df -h` at 2026-11-24
  18:39Z, before the build), so it cannot be fetched without deleting another lane's checkpoint. The
  FP4-Local copy main pins is already on the box at main's revision. This is the declared deviation of
  checkpoint, and it is the "different checkpoint" the maintainer asked for against the dev stack's
  `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` (`1464274120d36a4d8fcaa934552334a7d83ce0fd`), which
  main's loader cannot serve.

Identity proof, captured before the first boot and again at each boot:

- HF cache ref: `~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local/refs/main` =
  `b9ce18a6887e18c089fdea8509a33e63429a3300` (read with `cat`, stored in `out/phase0/`).
- Snapshot dir: `.../snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300/`, 96 GiB (measured `du -sh`),
  containing `config.json` (its sha256 recorded), `model.safetensors.index.json` (sha256 recorded, plus its
  tensor count), `tensors/` shards, `chat_template.jinja`, `tokenizer.json`.
- Served path inside the container: `/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300`, the
  whole HF model directory mounted read-only at `/models/qwen38` (the snapshot's shard symlinks resolve inside
  it). The boot log's model-directory line and `GET /v1/models` are captured per boot.

## 4. The lever: TF_FLASHNEXT_SHARED_DRAFTS

- Reader: `zig/src/families/flashnext/cuda_lanes_draft.zig:45-48` -
  `/// TF_FLASHNEXT_SHARED_DRAFTS=0: greedy chains keep the engine's stop rule beside other streams too.` and
  `return @import("sys").environment.read(bool, "TF_FLASHNEXT_SHARED_DRAFTS", true) catch true;`
- Effect: `cuda_lanes_draft.zig:32-40` - a round's greedy chains keep the engine's confidence stop while one
  stream is open, and `shared_stop: f64 = 0.6` only when `sharedRule() and busy(&self.lanes)` (more than one
  stream decoding, filling or resuming). So arm 1 (=1, the shipped default) stops greedy chains beside another
  open stream at 0.6; arm 0 (=0) keeps the engine's own rule (default `TF_FLASHNEXT_CONFIDENCE=-0.4`, product
  >= 0.4) in shared rounds too.
- Declared in the environment table: `docs/environment.md:201` - "Exactly `0` or `1`; default on".
- Nothing else is set on either arm: no TF_/TENSORFOLD_ variable other than this one, no `--learn`, no
  `--spread`, no extra flags. The container's `Config.Env` is captured at every boot and must differ between
  the arms only in this variable.

## 5. Arms, server, and what is equal

- Same image, same launcher (`~/work/SharedDraftsMain/sd-boot.sh`), same checkpoint, same context window,
  same `--parallel`, same prompt-cache budget, same temperature default, same client, same prompts.
- Serve command (both arms):
  `tensorfold-native serve /models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300 --name Qwen3.8-Flash-Next --host 0.0.0.0 --port 8888 --context 32768 --parallel 8 --prompt-cache-gib 3 --temperature 0`
- Arm 0: `TF_FLASHNEXT_SHARED_DRAFTS=0`; arm 1: `TF_FLASHNEXT_SHARED_DRAFTS=1`. Container name `sd-main-tf`
  so production's own stop script cannot touch it; port 8888 is free because production is stopped inside the
  lock.
- `--context 32768` and `--parallel 8` are the shape main's own table measures on one GB10
  (`docs/recipes/flash-next-cuda.md:238-242`: a 32,768-token window admits 7-8 streams of 1.21 GiB, engine
  73.2 GiB). The prompt-cache budget is 3 GiB rather than the 8 GiB first drafted: the documented
  engine + 8-stream + reserve figure leaves about 10 GiB of headroom on a 123 GiB visible RAM, so 3 GiB keeps
  the admission comfortably inside it while still holding every small state the cached control needs.
  Concurrency is varied by the client (1, 2, 4, 8), never by rebooting with another `--parallel`.

## 6. Counters: how this engine exposes drafts and acceptance

- Aggregate, Prometheus text at `GET /metrics`: `tensorfold:mtp_drafted_total` ("Draft tokens verified on
  finished requests"), `tensorfold:mtp_accepted_total` ("Draft tokens kept on finished requests")
  (`zig/src/server/metrics.zig:141-142`, repeated under vLLM names as
  `tensorfold:spec_decode_num_draft_tokens_total` / `..._accepted_tokens_total` at `:221-222`),
  `tensorfold:decode_rounds_total` (`:149`), `tensorfold:prompt_tokens_total`,
  `tensorfold:generation_tokens_total`, `tensorfold:prompt_tokens_cached_total` (`:201`).
- Per reply: the response's `tensorfold` block carries `token_sha256` (64 hex, `zig/src/server/tokens.zig:126`),
  `token_sha` (12 hex), `tokens_per_second`, `seconds`, `time_to_first_token`, `prefill_seconds`, and a
  `speculative` object with `rounds`, `drafted`, `accepted`, `acceptance_rate`
  (`zig/src/server/chat_generation.zig:435-441`, emitted at `:462`). `return_token_ids: true` also returns the
  reply's token ids (`chat_generation.zig:421-426`).
- Per request, the server log writes
  `done ... rounds=<r> accepted=<a>/<d> ttft=<s> decode=<s> ... tok/s=<v>`
  (`zig/src/server/chat_generation.zig:484`); the window keeps each boot's `docker logs`.
- The harness reads all three (metrics scrape before/after each cell, the reply block, the log) and reports the
  readings. A counter that cannot be read is reported as absent, never substituted.

## 7. Cells, order, and the client

Client: `~/work/SharedDraftsMain/sd_harness.py`, which imports upstream's own stream reader and evidence
helpers (`tools/bench_stream.py`, `tools/bench_evidence.py` from the built tree) so the SSE parsing, piece
timing, `token_sha256` and `speculative` extraction are the repository's, not a re-implementation.

Requests: chat completions, `temperature: 0` (greedy), `chat_template_kwargs: {"enable_thinking": false}`,
`max_tokens: 512`, `ignore_eos: true`, `stream: true`, `stream_options.include_usage`, `return_token_ids: true`,
`draft: true`. Prompts: 4 prose and 4 code, fixed strings; each pass prefixes a nonce
`Benchmark session sd4803-c<C>-p<pass>-i<index>. ` that is identical on both arms and different between passes,
so every decode pass is cold on the server's prompt cache and the two arms see byte-identical prompt strings.

Fresh boot a cell:
- C=1: arm 0 then arm 1; C=2: arm 1 then arm 0; C=4: arm 0 then arm 1; C=8: arm 1 then arm 0.
- Cached two-stream control: its own pair of boots, arm 1 then arm 0.
- Each boot: idle TTFT cases, then the cell's passes on that fresh server, then the container is stopped.
- Decode cell: 3 passes, each pass a barrier-started set of C streams with distinct prompts. Reported: per
  pass the aggregate decode rate (sum of tokens after the first / (last token of any stream - first token of
  any stream)), per-stream decode rate ((tokens-1)/(last-first)), per-stream and median TTFT (client clock),
  the server's own `time_to_first_token` and `tokens_per_second`, token counts, and per reply `token_sha256`
  plus the first 64 token ids.
- Idle TTFT: 2 reps at a 1k-token prompt and 2 at an 8k-token prompt, one stream at a time, server idle,
  `max_tokens: 64`; `cached_tokens` must read 0 (cold). This is the "TTFT idle" series.
- Cached two-stream control: prime prompt A and prompt B with one stream each (512 tokens), then send A and B
  together as two streams and record `usage.prompt_tokens_details.cached_tokens` and
  `tensorfold`/`speculative` per reply, plus the `/metrics` `prompt_tokens_cached_total` delta.
- Thermals: `nvidia-smi --query-gpu=temperature.gpu,clocks.sm,power.draw,memory.used` before and after every
  pass, as `docs/receipts/ParityAB/window.sh`'s `gpu()` does.
- Every boot's `docker inspect` (image id, command, env), `/health`, `/v1/models`, `/metrics` body and full
  `docker logs` are written under `out/<arm>/<cell>/`.

Repeats and the rerun rule (declared before the first cell): decode = 3 passes, median reported; idle TTFT =
2 reps, median. After scoring, a level whose three decode passes span more than 5 percent (max/min-1) on
either arm is re-booted for BOTH arms in reverse order once (the pair stays adjacent); a level still over 5
percent after that is reported with its spread and marked noisy, not re-run again.

## 8. Acceptance checks (computed by the window's scorer, from the stored evidence)

1. For every (level, pass, stream index) the two arms' `token_sha256` are equal; a difference names the first
   divergent token by comparing the stored token-id lists. Same for the cached control's two streams.
2. A concurrency table: both arms' decode aggregate, per-stream median, TTFT (client and server), and the
   `mtp_drafted_total` / `mtp_accepted_total` / `decode_rounds_total` deltas; the D1/D0 ratio per column; the
   cached two-stream cell separately.
3. Identity: image id and main sha from the build log, checkpoint revision and file hashes, the per-cell
   evidence bundle, and the restore proof (`/health` 200, pinned production image id, and
   `check-prod-env.py --inspect` on a fresh `docker inspect` reporting its rows compared with 0 problems).

## 9. Window, lock and restore

- Driver: `~/work/SharedDraftsMain/sd-window.sh`, launched detached (`nohup`, own log, `WINDOW-DONE`
  marker), queued on `flock -o -w 43200 ~/work/gpu.lock` exactly as `docs/receipts/ParityAB/window.sh` queues:
  the outer process waits for the lock, the inner runs the matrix and is the one that stops production.
- Preflight (production still live): live production image/cmd/env, `/health` 200, the production
  `check-prod-env.py`, the image ids, the checkpoint file hashes, host facts, the running lane's lock holder.
- Inside the lock: production is stopped with its own recipe stop script, then one smoke boot of arm 1 proves
  the loader admits this checkpoint with the prompt cache and the harness reads a complete reply (a smoke
  failure ends the window there, so a wrong serve configuration cannot burn the matrix), then the cells run in
  the order above. An EXIT trap stops my container and restores production from `~/qwen6-start-prod.sh` (its
  own launcher, its pinned image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`), waits for `/health` 200
  and runs `check-prod-env.py --inspect <fresh inspect>` (117 rows compared, 0 problems expected). A retry with
  the same trap runs if my serve still holds the port.
- No repository commits, no public text. All artefacts stay under `work/SharedDraftsMain/` (local) and
  `~/work/SharedDraftsMain/` (spark6).

## 10. Declared limits

- One checkpoint, one box, one window; no second build (a clean main image is a fixed artefact).
- The prompt cache is on (3 GiB) because the cached two-stream control needs it; every decode pass is made
  cold by the per-pass nonce, and the idle TTFT cases are checked to read `cached_tokens = 0`.
- Declared fallback: if the smoke boot refuses the 3 GiB prompt cache (an admission message in its log), the
  window retries once at 1 GiB for BOTH arms, logs `SMOKE-RETRY`, and every boot's `cmd-boot.json` carries the
  budget actually used. No other setting changes.
- 512-token replies with `ignore_eos`, so a reply cannot end early and the hashes cover the same token count.
- If the checkpoint's prompt cache and drafts interact badly (a refusal at boot or a control that shows no
  cached tokens), the window reports exactly that, with the boot log line or the counters, and does not
  substitute another measurement.
