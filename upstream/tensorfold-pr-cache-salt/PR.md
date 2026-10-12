# Upstream PR (not posted): TensorFold main, vLLM's cache_salt

Target: `ashhart/TensorFold`, base `e7c523eb` (main, 2026-10-11). Main had no `cache_salt` or anything like it (only `TENSORFOLD_SEED_SALT`, which keys sampling seeds, not the cache). Independent of `../tensorfold-pr-evict-branch-point/`; both touch `victimBut`, whichever merges second rebases.
Origin: the `cache_salt` half of our recipe patch 0027 (`../zig-pr-prompt-cache-whole/`), ported onto main's store, which has grown rewind states, learned states on disk, a paged store, warm passes and reply keeps since the recipe's pin.
Evidence: spark6 `~/work/lanes/tfevict/` (worktree `w-salt`; logs `e/salt3*`, `e/msalt3.mac.log`, `e/mbase.mac.log`, `final-salt.out`, `mut-salt{1,2,3,4}.out`). Files here: `pr.diff` (`git apply --check` clean on e7c523eb), `mutants.tsv` (+ `mut.sh`, `subst.py`, `t.sh`, `gates.sh`, `lean_diff.py`, `mac.sh`, `xcrun`).
Not covered, stated in the body: the paged store (`prompt_radix.zig`) has no backend on main, so no request reaches it; it is not salted here.
Not posted: the owner approves the text first.

---

**Title:** cache_salt: vLLM's prompt cache salt on chat, completions and responses

**Body:**

## What this changes

`cache_salt`, vLLM's request field, now keys the prompt cache: a request resumes only prompt states kept under the same salt, so clients that share a server cannot resume each other's prefixes, or learn from a quick first token that someone else sent one. Requests without a salt share their states as before.

- `/v1/chat/completions`, `/v1/completions` and `/v1/responses` take it. Absent or null is no salt; any other value that is not a non-empty string is a 400 before anything reaches the engine, as vLLM refuses it.
- The store keys every state by it: a lookup, a keep, the state near a rewind that serves it, the room a pass makes before it starts, a peer's forget, shared system cuts (shared within their salt) and eviction (another salt's longer state never supersedes a state; a lookup's rewind state is its own salt's).
- Learned states on disk (`--learn`) are the unsalted ones: later sessions and servers read them back whatever their salt, so a salted request neither writes nor reads them.
- Every host passes the salt: the lane host (its keeps, its warm passes, and the stream, for a backend that keeps a finished reply itself, as Qwen3.8-27B does), the serial host (marks, warm passes and finished replies) and Flash Next's Mac host. The next turn's background prefill after a chat reply keeps the conversation's next state under the reply's salt (vLLM had to fix a dropped salt in the same place, its Responses tool continuations: GHSA-935w-9g4m-p28p).
- Speed-up mode on two Macs: rank 1 keeps one copy for a token prefix, so rank 0 now tells it to drop that copy only when no other kept state (another salt's at the same tokens) still has the same name. Without that, two clients with one system prompt would make each other's turns read their prompt from the start.
- `Store.deinit` takes each state out of the list before freeing it, so a family's drop (the check above) never reads a freed state.
- `docs/api.md`: the field, the 400, and the Responses pass-through list.

Not covered: the paged store (`prompt_radix.zig`) has no backend yet and no request reaches it; its first backend can key it the same way.

## Receipt

- Environment, with the TensorFold commit, MLX or PyTorch version, machine and GPU, checkpoint and revision: TensorFold `e7c523eb` (main), Zig 0.17.0, Linux aarch64 on a GB10 host, host tests only (CPU). No checkpoint.
- Exactness, from `tools/bench_concurrent.py --alone --serial` or `token_sha` against `"draft": false`: not run. No row arithmetic changes; the salt only decides which kept states a request may resume. In the store tests every resumed pass equals a fresh one.
- Decode speed before and after, from `tools/bench_openai.py`: not run (no decode path changed).
- Prompt speed before and after, from `tools/prefill_cold.py`: not run. The store's scans compare one more integer per kept state.
- Tests run, with pass, fail and skip counts:
  - `zig build test`: main 451/451; this change 461/461.
  - `zig/tests/server/zig_test.sh`: main 127/127 and 104/104; this change 130/130 and 113/113.
  - New tests: the store (a salted prompt resumes only its own salt's states and the unsalted share theirs; shared cuts within a salt; no learned states written or read under a salt; another salt's longer state supersedes nothing; a lookup's rewind is its own salt's, and a salted turn's rewind goes last as an unsalted one's does; room made before a pass for a state another salt holds at the same tokens; the store frees states out of its list), the lane host and the serial host (marks, warm passes, finished replies and the stream's salt, each resumed only under its own salt), and the server (the salt reaches the engine from all three routes and from the chat's warm pass; null and absent are none; `""`, numbers, booleans, arrays and objects are a 400 with nothing submitted).
  - Mutants, each one replacement in a copy of this change, judged by the suites' exit code with the named test failing: 30 of 30 killed, across the store, both hosts and the server. Five first-written ones removed a parameter's only use and did not compile, so they proved nothing; they were rewritten as behaviour changes (the check made dead instead of removed), and only the rewritten ones are counted.
  - The macOS-only files (Flash Next's Mac host, the Qwen3.8-27B host, the Flash Next reuse tool) were compiled for aarch64-macos on Linux with the frameworks unlinked: no source error, and the link stops at the same 17 Objective-C symbols as on main. The check catches an error injected into each of those files.
  - `python3 tools/zig/lean_check.py` reports no problem this change adds; `zig fmt --check` passes on the changed files.
- Not run, and why: no GPU, Metal or two-Mac run. The engines that use this store (CUDA Nemotron and GLM, and on a Mac Flash Next and Qwen3.8-27B) were not run on this change; I have no Mac.

## Checklist

- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [ ] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo. (Resumed equals fresh in the host tests; no engine run.)
- [x] No precision traded for speed. If the bits change, the description says which sums change and why.
- [ ] Prompt processing is no slower than the last release. (Not measured on a GPU.)
- [x] The description says which platforms I ran, Metal M1 to M5 and CUDA, and which I could not.
- [x] New tests fail before the change, pass after it, and skip cleanly without their dependency.
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths. No AI attribution lines.
