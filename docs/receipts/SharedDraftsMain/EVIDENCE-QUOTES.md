# Evidence quotes for issue #4803 (recorded before the window; every line re-checked at the commit built)

Commit built: `9a38b1f7b33863507cdea47e88207d8b3bea3f22`, tree `6e00d270fec84cb6decb784e148712d4d27b5f03`.

## The lever

- `zig/src/families/flashnext/cuda_lanes_draft.zig:45-48`
  - `/// TF_FLASHNEXT_SHARED_DRAFTS=0: greedy chains keep the engine's stop rule beside other streams too.`
  - `fn sharedRule() bool { return @import("sys").environment.read(bool, "TF_FLASHNEXT_SHARED_DRAFTS", true) catch true; }`
- `zig/src/families/flashnext/cuda_lanes_draft.zig:32-36`
  - `pub const Rule = struct { greedy: usize, greedy_stop: f64 };`
  - `pub const shared_stop: f64 = 0.6;`
  - `pub fn rule(self: anytype, width: usize) Rule { ... const stop = if (sharedRule() and busy(&self.lanes)) shared_stop else self.confidence; return .{ .greedy = greedy, .greedy_stop = stop }; }`
- `docs/environment.md:201`: `| TF_FLASHNEXT_SHARED_DRAFTS | Exactly 0 or 1; default on |`

## The chain depths and the engine's stop rule (both arms keep these defaults)

- `zig/src/families/flashnext/cuda_mtp.zig:33`: `pub const default_depth: usize = 6;`
- `zig/src/families/flashnext/cuda_mtp.zig:35`: `pub const default_depth_greedy: usize = 8;`
- `zig/src/families/flashnext/cuda_mtp.zig:48`: `pub const default_confidence: f64 = -0.4;`
- `zig/src/families/flashnext/cuda_lanes_draft.zig:31`: `pub const default_wide: usize = 4;` (the round width up to
  which greedy chains keep 8; wider rounds take 6).
- `docs/recipes/flash-next-cuda.md:113`: `TF_FLASHNEXT_DRAFTS` (1 to 15, default 6) and
  `TF_FLASHNEXT_CONFIDENCE` (default -0.4) set the head's chain.
- `zig/src/families/flashnext/cuda_mtp.zig:50`: `TF_FLASHNEXT_CONFIDENCE c > 0: a later draft only at or above c;
  c < 0: while p1 * ... * pj >= -c; 0: every draft.` So arm 0 (no shared override) keeps a later draft while the
  drafts' probabilities multiply to at least 0.4; arm 1 beside another open stream keeps it only at or above 0.6.

## The checkpoint

- `docs/recipes/flash-next-cuda.md:236`: `### The ModelOpt checkpoint on one GB10`
- `docs/recipes/flash-next-cuda.md:238-241`: `nvidia/Qwen3.8-Flash-Next-FP4-Local` (revision `b9ce18a6`) on a GB10
  (128 GB, driver 580.178, CUDA 13.3), greedy, `--prompt-cache-gib 0`, ... three runs of the defaults at a
  32,768-token window alternated with other settings in one session.
- `docs/hermes-agent.md:51`: On a DGX Spark (GB10) with TensorFold 1.2.3 serving
  `nvidia/Qwen3.8-Flash-Next-FP4-Local` (`--context 131072 --parallel 2 --dashboard`).
- Full revision, main's receipts: `docs/receipts/flashnext-draft-head/README.md:19`,
  `docs/receipts/flashnext-readout-fused/README.md:19`, `docs/receipts/flashnext-prompt-chunk3072/README.md:9`:
  `nvidia/Qwen3.8-Flash-Next-FP4-Local`, revision `b9ce18a6887e18c089fdea8509a33e63429a3300`.
- Main's own build command, same receipt: `zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast fatbins install native`
  with Zig 0.17.0 and nvcc 13.3.

## The counters

- `zig/src/server/metrics.zig:141-142`:
  - `try gauge(w, "mtp_drafted_total", "counter", "Draft tokens verified on finished requests.", snap.drafted);`
  - `try gauge(w, "mtp_accepted_total", "counter", "Draft tokens kept on finished requests.", snap.accepted);`
- `zig/src/server/metrics.zig:149`: `decode_rounds_total` ("Decode rounds used by finished requests").
- `zig/src/server/metrics.zig:201`: `prompt_tokens_cached_total` ("Prompt tokens of finished requests restored
  from kept prompt states").
- `zig/src/server/metrics.zig:221-222` (vLLM names): `spec_decode_num_draft_tokens_total`,
  `spec_decode_num_accepted_tokens_total`.
- Per reply, `zig/src/server/chat_generation.zig:435-441`: a `speculative` object with `rounds`, `drafted`,
  `accepted`, `acceptance_rate`.
- Per reply, `zig/src/server/chat_generation.zig:418-419`: `token_sha` (12 hex) and `token_sha256` (64 hex) of
  the reply's token ids, from `zig/src/server/tokens.zig:126` (`tokenSha256`).
- Per reply, `zig/src/server/chat_generation.zig:421-426`: `return_token_ids: true` adds the reply's token ids to
  the same `tensorfold` block.
- Server log, `zig/src/server/chat_generation.zig:484`: `done ... rounds= accepted=/drafted= ttft= decode= ... tok/s=`.
- Cached prompt tokens per reply: `zig/src/server/openai.zig:273-274` writes
  `usage.prompt_tokens_details.cached_tokens` from `reply.cached_tokens` (`chat_generation.zig:458`).

## Sources checked for a drafts-and-prompt-cache refusal

None found: `zig/src/server/cli.zig` refuses `--prompt-cache-gib` with `--prompt-cache-disk` only in the ways
listed at `:212-222`; the Flash Next snapshot path keeps the MTP head's cache rows for a drafting stream
(`docs/recipes/flash-next-cuda.md`, in "What the core runs and what the family runs"), which is what the cached
control exercises.
