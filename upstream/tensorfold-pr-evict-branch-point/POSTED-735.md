**Title:** Prompt cache: a state a conversation resumes again is a branch point, not superseded

**Body:**

## What this changes

When the prompt cache needs room it frees first a state that a longer state, kept by a later prompt, extends (`victimBut` in `zig/src/core/prompt_cache.zig`; `pick` in `zig/src/core/prompt_radix.zig`). That's right for a conversation that has grown past its old turns.

It's wrong for the state several continuations branch from: a re-sent turn, a regenerated or edited reply, or an agent that starts each step from the same history. Once one of them has kept its own longer state, the state the next one needs counts as superseded, and the next prompt that keeps anything (a long prompt keeps its history) evicts it first. Every later continuation then prefills the whole history again and keeps nothing at that history either, so the conversation never recovers.

A kept state that is resumed again after a later prompt kept a longer state extending it is now a branch point: the superseded rule skips it, and it only goes as the least recently used, like a shared system cut does. A state resumed once and then extended is still superseded first, as before, so a conversation that grows turn by turn frees its old turns first.

Both stores get the rule (the paged store has no backend yet; the rule is the same there).

Found this on a Qwen3.8 Flash Next serve built on an earlier TensorFold whose store has this same rule. One GB10, a ~100k-token conversation, three other streams decoding, and other 1k-8k token prompts in between its turns:

- without the rule, 18 of 20 turns lost the conversation's state and prefilled its ~100k tokens again (about 35 s, against about 1.2 s resumed);
- with the branch-point rule (and a second rule for short whole-prompt states, which main doesn't have), 0 of 20 were lost, and 0 of 383 over a 20-minute run.

On main the same sequence fails in a host test, below.

The cost: a branch point that's never resumed again sticks around until it's the least recently used state, where it used to go first.

## Receipt

- Environment, with the TensorFold commit, MLX or PyTorch version, machine and GPU, checkpoint and revision: TensorFold `0efbd447` (main), Zig 0.17.0, Linux aarch64 on a GB10 host, host tests only (CPU). No checkpoint.
- Exactness, from `tools/bench_concurrent.py --alone --serial` or `token_sha` against `"draft": false`: not run. The change is eviction order only: no row arithmetic, kernel or reply path changes. In every new test a resumed prompt pass equals a fresh one (the test family's running sum).
- Decode speed before and after, from `tools/bench_openai.py`: not run (no decode path changed).
- Prompt speed before and after, from `tools/prefill_cold.py`: not run. A resume now scans the kept states once for a longer one that extends it, the same scan eviction already makes for each state.
- Tests run, with pass, fail and skip counts:
  - `zig build test`: main 616/621 (5 skipped); this change 623/628 (5 skipped).
  - `zig/tests/server/zig_test.sh`: main 155/155 and 96/96; this change 155/155 and 100/100.
  - Before the fix (main plus only the new tests): the flat store's test fails (`expected 100117, found 0`: the conversation's next turn prefills from the start after a 6k prompt made room) and so does the paged store's (`expected 20, found 0`); the other two new tests pass on main as they should (a state resumed once and then extended is still superseded first; a turn's rewind state is not superseded by the history state its own prompt kept).
  - Mutants, each a single replacement in a copy of this change, judged by the suites' exit code with the named test failing: 7 of 7 killed. Never marking a branch point, ignoring the mark in `victimBut`, marking every resumed state, dropping the "kept by a longer prompt" condition from the extension check (killed by the rewind test, which I added for it), and the same three for the paged store.
  - `python3 tools/zig/lean_check.py` reports no problem this change adds; `zig fmt --check` passes on the changed files.
- Not run, and why: no GPU or Metal run. The engines that use this store (CUDA Nemotron and GLM, and on a Mac Flash Next and Qwen3.8-27B) were not run on this change; I have no Mac, and the GB10 measurement above is from the earlier TensorFold.

## Checklist

- [x] Every token still goes through the lane rounds. No serial path, and nothing that needs drafts off.
- [ ] Drafted output equals `"draft": false`, a resumed prompt equals a fresh one, and concurrent equals solo. (Resumed equals fresh in the host tests; no engine run.)
- [x] No precision traded for speed. If the bits change, the description says which sums change and why.
- [ ] Prompt processing is no slower than the last release. (Not measured on a GPU.)
- [x] The description says which platforms I ran, Metal M1 to M5 and CUDA, and which I could not.
- [x] New tests fail before the change, pass after it, and skip cleanly without their dependency. (The two tests for the bug fail on main; the other two pin behaviour this change keeps and pass on both.)
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths. No AI attribution lines.
