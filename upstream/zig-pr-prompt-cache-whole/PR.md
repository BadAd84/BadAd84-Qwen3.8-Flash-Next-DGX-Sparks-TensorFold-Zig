# Upstream PR (not posted): patches/0027: whole-prompt states, so a repeated prompt starts with no forward, and vLLM's cache_salt

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `fea45ba` (main, 2026-10-11); open from me: #34-#36, #42-#50, #53-#57.
Evidence: lane r3-promptcache (`~/work/lanes/r3-promptcache/`: hold1.out, hold2.out, pcheck.py, reuse-ours.log, mut.out; image `r3pc-whole`), merged image `zmerge7` (`zrm-m7`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md` (zmerge7). Clean stack: spark6 `~/work/lanes/b4-pack/` (tf branch `b4` = r1e stack 0001-0024 + 0025-0028, patches `pt/`, image `tensorfold-qwen38:zpr-b4c-stack`, host tests `t.log`, `hostmut4c.out`, GPU `b4q1c.log` / `runs/mut-b4c*.log`, evidence `~/work/gpuev/runs/b4c-*`).
Restyled: work/restyle-b4/prompt-cache-whole.final.md (adam-style, reviewed; approved 2026-10-12)

---

**Title:** patches/0027: whole-prompt states, so a repeated prompt starts with no forward, and vLLM's cache_salt (a 64k replay's first token in 0.05 s instead of 21.4 s; replies byte-identical)

**Body:**

## Description and Motivation

The prompt cache keeps a state at a conversation's history mark (7 tokens before the end of a chat prompt of 4,096+ tokens) and at shared system blocks. A prompt sent again as it is, or a completion prompt of token ids (RigMark's prefill shape, an agent's retry, a tool loop's resend), keeps nothing: it runs its whole prefill again, about 22 s at 64k tokens.

`patches/0027-flash-next-whole-prompt-states-cache-salt.patch`:

- `TENSORFOLD_PROMPT_CACHE_WHOLE=1` (this PR's setting; the engine's default is off): a prompt also keeps a state at its very end, taken after its first token is drawn (no extra prompt call, no cost on the cold path), carrying the last logits row and the last row's streams. The same prompt then resumes with nothing left to prefill: the engine restores the state and draws its first token from the kept row. A longer prompt resumes from it like from any other state.
  - `TENSORFOLD_PROMPT_CACHE_WHOLE_MIN` (default 1024) is the shortest prompt that keeps one; a chat prompt of 4,096+ tokens keeps its history mark as before.
  - Both settings are strict (`0`/`1`, a count from 1; anything else stops the start with the setting named), and `1` on an engine that can't resume a prompt's very end is refused.
- Eviction keeps a long conversation's state:
  - a prompt under `min_prompt` (4,096 tokens, so one that keeps only its whole-prompt state) frees only other such prompts' states, oldest first, and when those can't make room it keeps nothing and frees nothing;
  - a state its conversation resumed again after a later turn had already extended it (a re-sent or forked turn) is a branch point, which the "a later turn superseded it" rule no longer evicts first (it goes only as the least recently used);
  - a state kept inside a longer prompt never replays a prompt that ends there (that prompt's own whole state replaces it).
- `cache_salt` (vLLM's field): a request's salt keys every state it keeps and every state it may resume, so prompts under different salts never share a state; unsalted prompts share theirs as before. A non-string or empty salt is a 400.
- `tensorfold reuse` (the engine's prompt-reuse check) also runs every prompt kept at its very end: the cold reply with the keep, the replay after another prompt left its own row in the sequence's last-row streams, the replay forked into another sequence, and the extension, each against its fresh prefill, tokens and rounds, drafts and accepted drafts.

Why the replies don't change: a whole state holds exactly what the prompt's last pass left (the cache rows, the recurrent state, the last row's streams and its logits row), and the first token is drawn from that row with the request's own sampling.

Why the eviction rules: while measuring this patch on our merged build, a kept ~100k conversation was lost under ordinary traffic. The store frees first a state that a longer kept state of its salt extends, then a short prompt's, then the oldest. Once a turn of the conversation has kept its own longer state, the state every next turn resumes counts as "extended", so it goes first, and two kinds of request free it:

- a short prompt's whole state (a cold 1k prompt): this patch's own trigger, since before it short prompts kept nothing;
- a long prompt of 4k-8k tokens: the existing rule, which fires with whole-prompt states off too (`TENSORFOLD_PROMPT_CACHE_WHOLE=0`).

Every later turn then misses and prefills its ~100k tokens again, about 35 s instead of about 1.2 s, because a turn that starts from 0 keeps nothing near 100k.

A ~100k conversation with three streams decoding and 200 other prompts of 1k-8k tokens (chat and completions, with and without a fresh `cache_salt`), its next turn after every tenth:

- with whole states on: 20 of 20 turns lost;
- with them off: 18 of 20;
- with the two rules above: 0 of 20 (and 0 of 12 re-sent turns).

The rules remove both paths: short prompts free only short states (or keep nothing), and a resumed turn that later turns already extend is a branch point that the "superseded" rule never takes. The cost: when the budget holds only longer prompts' states, a short prompt's whole state is refused (60 in that run), so that prompt prefills again on a replay, as every short prompt did before this patch.

Memory: a whole state adds one logits row (248,320 x 2 bytes, 485 KiB) beside its rows, inside the prompt cache's existing budget. At the defaults the start's estimate is unchanged (about 94 GiB needed, 118 GiB available); the engine's sequence memory is 31.37 GiB (31.21 with this batch's settings off on the same image and 30.33 on the stack without this batch: the spread between boots), and MemAvailable never went below 30.93 GiB over every probe above, the 200k needle included (29.21 GiB on the stack without this batch over the same probes).

Measured on one DGX Spark through the recipe's server: a 64k completion prompt sent again draws its first token in 0.052 s instead of 21.42 s (the full prefill), on the stack through this batch at the recipe's defaults. The table below has every length.

Measured by the lane on the campaign's build with #34-#36, #42-#50 and #53-#57 (`zmerge6`) vs the same build plus the lane's version of this patch, a full request (48-token reply included), seconds:

| prompt tokens | cold | replay with `0027` | replay without |
| ---: | ---: | ---: | ---: |
| 1,100 | 0.63 | 0.20 | 0.61 |
| 3,000 | 1.15 | 0.20 | 1.15 |
| 5,000 | 1.85 | 0.19 | 1.84 |
| 8,192 | 2.86-3.97 | 0.21 | 2.82 |
| 20,000 | 6.64 | 0.23 | 6.70 |
| 65,536 | 22.04 | 0.31 | 22.20 |

An extension of 64 tokens resumes in 0.29-0.50 s against a 0.63-22.3 s cold. RigMark's immediate-replay prefill column reads 2,988-3,159 tok/s without it and 1.29M-1.71M "tok/s" with it (5-50 ms to the first token).

### The whole stack on RigMark and time to first token, stock against ours

One DGX Spark, the recipe's own server (`start.sh`, the recipe's defaults otherwise), a fresh boot per arm, golden replies byte-identical in every arm. Columns:

- the recipe's last Python release (0.6.1, its published image);
- this recipe's Zig release 1.0.0 as published (`tensorfold-qwen38:zig-db28187`);
- that plus #34-#36, #42-#50 and #53-#57 as they stand after review round 1 (an image built from exactly `patches/0001`-`0024`);
- and that plus this batch (an image built from exactly `patches/0001`-`0028`, with this batch's `scripts/config.sh` settings).

The last two ran in one sweep (comparison ID `zrm-b4c`, 2026-10-11, golden 6/6 in both arms), the first two in their own sweeps on 2026-10-10.

Time to first token, client-measured to the first streamed token, median of 3, in seconds, thinking off. Cold prompts are new text; the warm turn is +2k tokens on a kept ~100k conversation:

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50, #53-#57 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| cold 1k, idle | 0.707 | 0.464 | 0.402 | 0.388 |
| cold 8k, idle | 3.819 | 2.989 | 2.616 | 2.604 |
| cold 32k, idle | 13.76 | 12.07 | 10.56 | 10.46 |
| cold 120k, idle | 57.20 | 49.62 | 42.15 | 42.02 |
| warm +2k turn, idle | 1.502 | 1.231 | 1.095 | 1.074 |
| cold 1k, 3 streams decoding | 0.922 | 0.537 | 0.466 | 0.463 |
| cold 8k, 3 streams decoding | 4.076 | 3.074 | 2.666 | 2.664 |
| cold 32k, 3 streams decoding | 14.88 | 12.18 | 10.69 | 10.61 |
| cold 120k, 3 streams decoding | 63.87 | 50.01 | 42.60 | 42.25 |
| warm +2k turn, 3 streams decoding | 1.927 | 1.321 | 1.180 | 1.156 |

[RigMark](https://github.com/alexellis/rigmark) (protocol 1.3.0, extra body `{"reasoning_effort": "low"}` like on its published card for this model; the receipts' medians):

| | Python 0.6.1 | Zig 1.0.0 | + #34-#36, #42-#50, #53-#57 | + this batch |
| --- | ---: | ---: | ---: | ---: |
| code / prose / structured decode, tok/s | 88.0 / 50.5 / 103.3 | 95.4 / 50.1 / 136.6 | 113.6 / 61.5 / 159.6 | 114.4 / 63.7 / 162.2 |
| time to first token, s | 0.28-0.29 | 0.18 | 0.15-0.16 | 0.14-0.15 |
| C1 / C2 / C4 aggregate, tok/s | 68.6 / 94.9 / 129.4 | 59.0 / 97.7 / 150.2 | 74.1 / 114.6 / 175.4 | 75.7 / 117.4 / 178.0 |
| prefill 8K / 32K / 64K cold, tok/s | not run | 2,723 / 2,636 / 2,520 | 3,115 / 3,055 / 2,975 | 3,239 / 3,103 / 3,015 |
| prefill 8K / 32K / 64K immediate replay, tok/s | not run | 2,725 / 2,639 / 2,496 | 3,157 / 3,061 / 2,977 | 1,854,233 / 1,321,877 / 1,332,656 (the whole-prompt state: no forward) |

The two stock arms passed RigMark's output gates 5/5 in code, prose and structured. The last two, in one sweep under their own comparison ID (so their decode prompts differ from the stock arms'), both passed code and structured 5/5 and prose 3/5: the same two prose prompts hit the 8,192-token reply cap in both (every prose reply the same length in both arms), so RigMark's cards for that sweep say not to headline them. I quote them for the comparison between the two.

RigMark's prefill section needs `/tokenize`, which the Python server lacks, so the Python arm skipped it.

One cell of the sweep went the wrong way: cold 1k with thinking on while 3 streams decode (0.466 -> 0.473 s, +1.5%, 3 samples; not in the table, which shows thinking off). A re-run of the cold 1k cells, 12 samples each, on fresh boots of both images (`zrm-b4c1k`, golden 6/6 both) settled it:

- thinking on, 3 streams decoding: 0.471 -> 0.462 s (-2.1%)
- thinking off, idle: 0.387 -> 0.376 (-2.7%)
- thinking on, idle: 0.414 -> 0.402 (-3.1%)
- thinking off, 3 streams decoding: 0.450 -> 0.444 (-1.2%)

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image's on every boot of every hold quoted here.
- `tensorfold reuse` on GB10 (prompts of 1.5k, 9k and 33k tokens, greedy and sampled, through drafted decoding): PASS on the stack through this batch (an image built from `patches/0001`-`0028`), 36 of 36 resumed runs equal their fresh prefills, exit 0. The whole-prompt runs (cold with the keep, replay after the extension ran on the sequence, forked replay, extension) are equal at 1,500, 9,000 and 33,000 tokens, greedy and sampled, rounds and drafts included (for example 17 / 40 / 30 at 33,000 greedy).
  - GPU mutants, judged by the check's exit code with the control build passing first: the replay drawing from the engine's last logits instead of the kept row (`e1-replay-stale-logits`), and the replay skipping the restore of the last row's streams (`e2-replay-no-tail`, which survived the lane's server-level check because it changes only the drafts' input; the replay-after-another-prompt run with rounds and drafts compared is there for it).
  - The control passes (36 of 36, exit 0) and both are killed (`reuse` exit 1).
- The lane's server check on GB10 (`pcheck.py`, 59 checks): PASS, 0 of 59 failed:
  - cold under a fresh salt reports 0 cached tokens;
  - the replay under the same salt, run after the other lengths' colds, reports the prompt's length cached and the same token sha, text and rounds / drafted / accepted at 1,100-65,536 tokens;
  - another salt is cold with identical replies;
  - a 64-token extension resumes and equals its own cold;
  - sampled pairs (temperature 0.8, seed 7) identical;
  - chat at 1,487 and 1,523 tokens (thinking off and on) replays with identical replies;
  - `cache_salt` 123 and `""` are a 400.

  Its 58 reply labels have the same sha and text with and without the lane's patch.
- Host tests (`zig build test` and `zig/tests/server/zig_test.sh`):
  - a whole prompt's state replays that very prompt, a longer one resumes from it and a shorter one keeps nothing;
  - a state inside a longer prompt never replays a prompt that ends there;
  - short prompts' whole states go first, and a long prompt frees them before an older long prompt's;
  - a short prompt's state never displaces a longer prompt's (the turn a conversation resumes outlives a stream of short cold prompts);
  - a short prompt whose state would need a longer prompt's room keeps nothing and frees nothing in vain;
  - a turn resumed again after a continuation kept a longer state is a branch point that its continuations never supersede;
  - prompts filling in slices keep their whole state;
  - the lane host replays a completion prompt from its whole state, salted lookups and keeps;
  - `cache_salt` absent or null is none, a non-string or empty one is refused;
  - the two settings are strict.

  Twenty-one mutants, each judged by exit code with the named test among the failures: 21 of 21 killed, each by the suite that holds its test (`zig build test` or `zig_test.sh`). Three were first written so that they didn't compile and were rewritten as real behaviour changes before they counted; one (a long prompt's eviction skipping the short prompts' states) first survived, and the test that kills it (a long prompt frees short prompts' whole states before an older long prompt's) was added.
- A kept conversation under a stream of other prompts, on GB10 through the recipe's server: a ~100k-token conversation primed, then for 20 minutes another prompt (1k-8k tokens of fresh text, chat and completions, with and without a fresh `cache_salt`) followed by the conversation's next turn (+2k tokens) while three streams decode; a turn that resumes below half its prompt counts as lost.
  - On the stack through this batch (an image built from `patches/0001`-`0028`): 383 turns, 0 lost, every turn resumed at the conversation's 100,117 tokens (time to first token median 1.16 s, at most 2.17 s), golden 6/6; the store evicted 813 other states and refused none.
  - The same run on an image of `patches/0001`-`0027` with this patch as first written, without the eviction rules: 7 of its 10 turns lost, from the fourth on (a 4,988-token completion prompt), each re-prefilling for about 35 s.
- The recipe's own tools on one GB10, each arm the recipe's `start.sh` at its defaults (8 x 262,144, fp8 KV, vision on): stock 1.0.0 (`tensorfold-qwen38:zig-db28187`, recipe main) and the whole stack through this batch (an image built from exactly `patches/0001`-`0028`, the recipe tree with every open PR of mine laid over main), in the same session. Stock / stack:
  - golden 6/6 both;
  - `tools/exact.py` PASS / PASS (482 / 527 drafts accepted; drafted equal to `"draft": false`, concurrent equal to one at a time);
  - `tools/exact.py --pad 3k` PASS / PASS (498 / 522);
  - `tools/toolcheck.py` 3/3 / 3/3;
  - `tools/needle.py` found / found at 199,730 tokens (prefill 89.33 / 73.16 s).

  The recipe has no `bench_draft` or `exact_prefill` file, so their forms ran as probes:
  - recipe sampling (temperature 1.0, top_p 0.95, top_k 20) with seed 1234, drafted, `"draft": false` and all at once: 38/38 replies identical to stock, drafted == `"draft": false` == concurrent for 11/11 prompts (1,479 drafts accepted);
  - cold greedy prompts of about 8k, 32k and 120k tokens, the 32k one again with `"draft": false`: 5/5 replies identical to stock;
  - 14 replies of four prompts arriving while others fill, identical to the stack without this batch.
- Every batch-4 setting off on the same image (`TF_FLASHNEXT_COST_RETIME=0`, `TF_FLASHNEXT_EARLY_DRAW=0`, `TF_FLASHNEXT_PROMPT_HEAD_SKIP=0`, `TF_FLASHNEXT_NGRAM_LATE=0`, `TENSORFOLD_PROMPT_CACHE_WHOLE=0`, `TF_FLASHNEXT_SHARED_EARLY_ROWS=0`, `TF_FLASHNEXT_SHARED_SLOT_LD=0`): golden 6/6; `exact.py` PASS (527 drafts accepted); 38/38 sampled and 5/5 prefill replies identical to stock and to the stack without this batch (an image of `patches/0001`-`0024` at its defaults, the same probes); prompts of 1,100-65,536 tokens sent again and extended by 64 tokens keep nothing and match their cold replies.
- Replay, the client's time to first token on the stack through this batch, `TENSORFOLD_PROMPT_CACHE_WHOLE` 1 against 0 on the same image (the probe streams a 48-token reply of a completion prompt cold under a fresh salt, then the same prompt again, then the prompt plus 64 tokens; every replay's reply equals its cold one). First token in seconds, on a fresh boot, every replay's reply, rounds, drafts and accepted drafts equal to its cold one:

  | prompt tokens | cold | sent again | plus 64 tokens | sent again with `TENSORFOLD_PROMPT_CACHE_WHOLE=0` |
  | ---: | ---: | ---: | ---: | ---: |
  | 1,100 | 0.414 | 0.003 | 0.095 | 0.405 |
  | 8,192 | 2.50 | 0.005 | 0.107 | 2.58 |
  | 32,768 | 10.42 | 0.025 | 0.133 | 10.64 |
  | 65,536 | 21.42 | 0.052 | 0.195 | 21.83 |

  With `TENSORFOLD_PROMPT_CACHE_WHOLE=0` the replay is the cold prefill again. The same probe run after the 200k needle, the 120k prompt and the concurrency probe had filled the budget with long prompts' states: 8k-64k as above, while the 1,100-token prompt kept no state (a short prompt frees only short prompts' states, and there were none) and prefilled again, as it did before this patch.
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory at the defaults (8 x 262,144, fp8 KV, vision on): the start's estimate is unchanged (about 94 GiB needed, 118 GiB available); the engine's sequence memory 31.37 GiB (31.21 with this batch's settings off on the same image and 30.33 on the stack without this batch: the spread between boots), and MemAvailable never went below 30.93 GiB over every probe above, the 200k needle included (29.21 GiB on the stack without this batch over the same probes).
- The patch is the measured code with our names taken out of the check's labels and comments, the salt parser moved to the server's field helpers (with its own test), the two settings made strict, and the engine default turned off (the lane had it on); the `reuse` check's whole-prompt runs now also compare rounds and drafts.

Other PRs from me: #34-#36, #42-#50 and #53-#57 (`patches/0010`-`0024` and two settings), and in this batch:

- #[0025's PR] (the boot cost table timed again)
- #[0026's PR] (the first token sooner)
- #[0028's PR] (the shared expert forked early and stored into its slot)

`patches/0025`-`0028` are written in that order on top of `0001`-`0024`: each applies with `git apply` after the ones before it. Every prefix of the stack builds and passes `zig build test` and the server and prompt-cache suite `zig/tests/server/zig_test.sh` (which `zig build test` runs on macOS only), each exit 0:

- through `0025`: 207/207 tests and 48 + 17
- through `0026`: 208/208 and 48 + 17
- through `0027`: 210/210 and 49 + 27
- through `0028`: 212/212 and 49 + 27

All of them add CHANGELOG/README/CREDITS lines in the same places, each adds a row to the same new patch table (as #35, #36, #42-#50 and #53-#56 do), and each adds `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase. Main's `## Unreleased` opens with "the image and `patches/` are unchanged"; that line stops being true once any patch PR merges, so I left your wording for the release.

So this PR's patch needs #35, #36, #42-#50, #53-#56, #[0025's PR] and #[0026's PR] merged first (logically it needs only #46's sequence pool, whose restore it extends).

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
