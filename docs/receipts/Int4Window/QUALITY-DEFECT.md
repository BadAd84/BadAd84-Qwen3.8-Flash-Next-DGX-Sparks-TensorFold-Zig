# The Int4Window quality block does not measure the checkpoints

Written 2026-11-22 from the fetched evidence only (`work/Int4Window/box/out`, hash-verified in
`FETCH.md`) and from the 2026-11-19 run's own rows (`work/QualityCmp/box/out/raw`, `work/QualityCmp/scores`).
No GPU was used, no box was touched, nothing was posted.

## Verdict in three lines

**Cause.** The requests are byte-identical to the 2026-11-19 run and the checkpoints are the same, so the
fall is not `max_tokens`, not a `stop` sequence, not the prompt bytes and not the grader: it is the engine
build. On these exact bodies the new build does not read the prompt it was given. Its replies answer the
prompt's own few-shot examples instead of the question (166 of 500 GSM8K replies on arm A and 145 of 500 on
arm B name the jelly-beans example, against 0 and 1 in the 2026-11-19 run), its recited MMLU-Pro option
letters stop matching the options that were sent (51.1 and 54.9 per cent of recited letters correct, against
82.6 and 82.5), and where the old build emits 76 tokens of correct chain of thought the new one answers a
different example, or starts the right one and stops after 25 tokens. The FP4 comparison isolates the image
(same flags, same checkpoint, same bodies); the INT4 comparison also differs in four serve flags, which does
not change the reading but does mean a re-run should match them (section 1).

**Verdict.** Not salvageable as scored and not salvageable by re-scoring: `needs a re-run` of all 1,664
items on both arms, on an engine build that reproduces the 2026-11-19 build's greedy text on these bodies.
Re-scoring with a corrected extractor moves GSM8K by 0.0 pp and MMLU-Pro by +2.5 and +1.5 pp, while the
no-extractor-can-do-better ceiling on GSM8K is 42.0 pp for INT4 and 11.8 pp for FP4 (against 97.4 and 97.2
in the earlier run).

**The INT4-versus-FP4 gap does not survive as a quality claim.** It is a real, statistically solid
measurement of this build (GSM8K 121 pairs against 22, p below 1e-6), but it is measured entirely inside a
build that misreads the prompt, and the failure mode is checkpoint-interacting: the same broken engine
leaves INT4 at 42.0 pp of GSM8K ceiling and FP4 at 11.8 pp, against 97.4 and 97.2 on the build both
checkpoints were measured on three days earlier. The magnitude is an artifact of the build and cannot be
carried to production.

---

## 1. What is identical, and why that excludes three of the four candidate causes

The harness (`quality_client.py`, sha256 `6853ccf9...cca2b6`, the same file hash in both runs and in both
arms' `*.meta.json`) builds one body per item and records its sha256. The body is:

```json
{"model": "Qwen3.8-Flash-Next", "prompt": "<the prompt file's bytes>", "max_tokens": 1024,
 "temperature": 0, "stream": true, "stream_options": {"include_usage": true},
 "stop": ["<|im_end|>"]}
```

Reconstructing that body for `gsm8k-test-6` from `stage/in/prompts/prompts_gsm8k.jsonl` reproduces the
recorded `body_sha256` exactly:

```
reconstructed body_sha256: 4ad8048ca63542450141e5e9e10ebbb0d40ca2bc0ed4b6ed5e7bfe9ac98a6898
I4W/A  recorded body_sha256: 4ad8048ca63542450141e5e9e10ebbb0d40ca2bc0ed4b6ed5e7bfe9ac98a6898  match True
QCMP/B recorded body_sha256: 4ad8048ca63542450141e5e9e10ebbb0d40ca2bc0ed4b6ed5e7bfe9ac98a6898  match True
```

So the hash covers every field that decides length or stopping, and equality of the hash is equality of
those fields, `temperature: 0` included. There is no `messages` array and no `chat_template_kwargs`; this is
a raw text prompt posted to `/v1/completions`.

Body and prompt hash agreement, Int4Window against the 2026-11-19 run, per benchmark:

| bench | pairs compared | ids common | `body_sha256` equal | `prompt_sha256` equal |
|---|---|---|---|---|
| gsm8k | I4W/A vs QCMP/A, I4W/A vs QCMP/B, I4W/B vs QCMP/A, I4W/B vs QCMP/B | 500 of 500 each | 500 of 500 each | 500 of 500 each |
| mmlupro | same four pairs | 1000 of 1000 each | 1000 of 1000 each | 1000 of 1000 each |
| humaneval | same four pairs | 164 of 164 each | 164 of 164 each | 164 of 164 each |

Inside each run the two arms also agree, 500/500, 1000/1000 and 164/164 on both hashes. The prompt files
themselves are byte-identical between the two runs:

```
prompts_gsm8k    3fc07867b74f49fd236256453629f79d1388271f3486337c3e45b79a4d03269d  (both)
prompts_mmlupro  d24100cec280965389803efb4d175a86f230e436501e10f1551b4b6c42da6608  (both)
prompts_humaneval d1644fe75c9cfe1d1fc64ed1ae1947b0fa1ac25491c90046bade2a0dd09700f6  (both)
```

And the tokenizer saw the same text: `prompt_tokens` is identical item by item in all four combinations
(gsm8k mean 1365.4, median 1361, 1330 to 1494; mmlupro mean 249.0, median 215, 85 to 1085; humaneval mean
141.9, median 125, 43 to 407), so the prompt is not re-rendered, not re-templated and not re-tokenised.

Request fields actually sent, per arm and benchmark (all four combinations identical):

| bench | `max_tokens` | `stop` | `temperature` | template fields |
|---|---|---|---|---|
| gsm8k | 1024 | `["<\|im_end\|>"]` | 0 | none (raw `/v1/completions`) |
| mmlupro | 1536 | `["<\|im_end\|>"]` | 0 | none |
| humaneval | 1024 | `["\nclass","\ndef","\n#","\nif","\nprint"]` | 0 | none |

Checkpoints are identical, revision for revision. The FP4 pair is a single-variable comparison: the two
serves differ only in the image, port aside. The INT4 pair is not: the earlier run's INT4 arm was
production's own launcher, and it differs from this window's in four flags as well as the image.

| item | Int4Window | 2026-11-19 run |
|---|---|---|
| INT4 checkpoint | `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` @ `1464274120d3...` | same revision |
| FP4 checkpoint | `nvidia/Qwen3.8-Flash-Next-FP4-Local` @ `b9ce18a6887e...` | same revision |
| INT4 serve | `--context 131072 --parallel 4 --no-thinking --kv-cache bf16` | `--context 262144 --parallel 8 --thinking --kv-dtype fp8` plus vision |
| FP4 serve | `--context 131072 --parallel 4 --no-thinking --kv-cache bf16` | the same flag string, port aside |
| other serve flags, all four | `--max-tokens 32768 --temperature 1.0 --top-p 0.95 --top-k 20` | the same |
| engine image | `1ece6e6d + r2 0001-0020` (B) and `+ int4 0021-0022` (A) | `zmerge8-kfix-e5139fcd8c6101c7` (A), `t5-b-c0eb2126` (B) |

What that buys and what it does not:

- **FP4 is a clean engine-build A/B.** Same checkpoint revision, same flag string, same bodies, same client,
  same `drafts: MTP + copies` serve line. What differs is the build: the image, plus the environment the
  window pins for both new arms (`env-block.txt`, identical on A and B, gated by `MATCH-OK`), of which the
  new arms register one experimental override, `TF_FLASHNEXT_KV_PAGES=4096`, and the earlier FP4 run
  registers none (`[tensorfold] profile: stable; registered overrides: none`). Its GSM8K level falls from
  96.8 to 8.8 per cent. That single pair is enough to establish that the serving build, and not the
  checkpoint, the prompt or the grader, is what changed.
- **INT4 carries a flag confound**, so its fall from 96.4 to 28.6 cannot be pinned on the image alone. It is
  still the same class of failure as FP4 (sections 3 and 5), both new arms fail together on the shared 20
  patch tree, and none of the four flag differences plausibly *breaks prompt reading*: bf16 KV is the more
  accurate option, `--no-thinking` matches the prompt's own pre-closed `<think></think>`, the context count
  does not change per-token arithmetic, and the stream count is ruled out as a necessary condition by the
  single-request replay in section 5(vi), which reproduces the concurrent run's text exactly. A re-run should
  still match production's INT4 flags so that the image is the only variable (section 7).

`(a)`, `(b)` and `(c)` are excluded as explanations of the difference on their own terms, independently of
the flag question: identical bodies cannot truncate at one `max_tokens` here and another there, identical
`stop` lists cannot fire differently, and identical prompt bytes with item-identical token counts cannot be
"rendered differently".

## 2. Reply shapes: the text itself changed

`finish_reason` counts, completion token and character distributions, per run, arm and benchmark. `stop`
means the serve ended the reply itself; `length` means the 1024/1536 cap ended it.

| run | arm | bench | stop/length | completion tok mean / med (min-max) | chars mean / med | under 300 chars | under 100 chars | `####` present |
|---|---|---|---|---|---|---|---|---|
| I4W | A | gsm8k | 451 / 49 | 335.6 / 236 (2-1024) | 1066.6 / 730 | 38 | 4 | 180 |
| I4W | B | gsm8k | 480 / 20 | 118.2 / 34 (9-1024) | 388.7 / 128 | 383 | 141 | 73 |
| QCMP | A | gsm8k | 497 / 3 | 146.5 / 124 (40-1024) | 343.1 / 268 | 286 | 9 | 497 |
| QCMP | B | gsm8k | 498 / 2 | 145.6 / 127 (45-1024) | 338.5 / 284 | 273 | 7 | 498 |
| I4W | A | mmlupro | 668 / 332 | 977.4 / 894 | 3382.4 / 3072 | 2 | 0 | n/a |
| I4W | B | mmlupro | 708 / 292 | 938.3 / 832 | 3215.2 / 2878 | 5 | 1 | n/a |
| QCMP | A | mmlupro | 797 / 203 | 897.2 / 776 | 3129.4 / 2930 | 1 | 0 | n/a |
| QCMP | B | mmlupro | 797 / 203 | 912.7 / 808 | 3207.2 / 2979 | 0 | 0 | n/a |
| I4W | A | humaneval | 159 / 5 | 87.4 / 48 | 254.8 / 147 | 135 | 57 | n/a |
| I4W | B | humaneval | 158 / 6 | 88.1 / 44 | 249.5 / 130 | 131 | 67 | n/a |
| QCMP | A | humaneval | 157 / 7 | 105.3 / 54 | 289.0 / 176 | 118 | 46 | n/a |
| QCMP | B | humaneval | 161 / 3 | 86.1 / 58 | 242.8 / 173 | 129 | 46 | n/a |

The GSM8K marker rate is the clearest single number: the prompt is an 8-shot chain-of-thought prompt (all
500 prompts carry exactly eight `Q:` examples before the question, verified across the file) whose examples
all end `#### <number>`, and the old build follows it in 497 and 498 of 500 replies. The new build follows it
in 180 and 73, and the replies that do not carry the marker are not formatted differently, they are answers
to a different question (section 5).

The 2026-11-19 run stopped itself (not `length`) on 497 and 498 of 500 GSM8K items, with a median of 123 and
127 completion tokens across those stopped replies; the new build stopped itself on 451 and 480, with a
median of 218 and 34. A `finish_reason: stop` at 34 tokens is the model emitting `<|im_end|>` in
mid-sentence, not a cap.

## 3. Where the new build's text first diverges from the old build's

Same checkpoint, same body, greedy on both sides. If the prompt were processed faithfully, the first sampled
token would agree. It does not, and the disagreement grows with prompt length. "first char" is how often the
reply starts with the same character; "LCP" is the longest common prefix against the old reply.

| bench | band of prompt tokens | arm | n | identical replies | first char equal | LCP median chars | LCP median share of old reply |
|---|---|---|---|---|---|---|---|
| humaneval | 0-64 | B | 10 | 10 | 10 (100%) | 74 | 1.00 |
| humaneval | 0-64 | A | 10 | 4 | 10 (100%) | 24 | 0.74 |
| humaneval | 65-128 | A / B | 77 | 5 / 4 | 77 / 77 (100%) | 8 / 7 | 0.05 |
| humaneval | 129-512 | A / B | 77 | 6 / 4 | 77 / 77 (100%) | 4 / 4 | 0.04 / 0.03 |
| mmlupro | 65-128 | A / B | 61 | 0 / 0 | 47 (77%) / 40 (66%) | 19 / 1 | 0.00 |
| mmlupro | 129-512 | A / B | 906 | 0 / 0 | 668 (74%) / 612 (68%) | 3 / 3 | 0.00 |
| mmlupro | 513-2048 | A / B | 33 | 0 / 0 | 10 (30%) / 9 (27%) | 0 / 0 | 0.00 |
| gsm8k | 513-2048 | A / B | 500 | 0 / 0 | 86 (17%) / 28 (6%) | 0 / 0 | 0.00 |

Two anchors bracket the threshold. The six golden cells are the only raw completions in the window at 28
prompt tokens or less, and the INT4 arm reproduces production byte for byte on all six (`out/P/golden.json`
was recorded on the production image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, per
`out/P/image.txt`):

```
golden-0: 24 tok, 2 completion tok, sha equal True   golden-3: 22 tok, 7 tok, sha equal True
golden-1: 24 tok, 215 tok, sha equal True            golden-4: 25 tok, 256 tok, sha equal True
golden-2: 28 tok, 13 tok, sha equal True             golden-5: 28 tok, 4 tok, sha equal True
```

The window's own `SANITY` chat probe is not a counter-example, and it is not evidence either: prompt 16
tokens, but it returned `OK.` on arm A (`token_sha ac29b1b45856`, 3 tokens) and `OK` on arm B
(`token_sha 9b3560a21927`, 2 tokens), so it already fails to be reproducible between the two arms of this
window while both arms record it as `SANITY ok`. It is a chat request, not one of the raw completions the
benchmarks use, and it is too short and too peaked to discriminate anything.

At the other end, all 10 HumanEval items whose prompt is 43 to 58 tokens reproduce the old build's text
exactly on arm B (`HumanEval/23`, `/83`, `/45`, `/27`, `/24`, `/53`, `/85`, `/55`, `/14`, `/28`), and the
first item at 69 tokens does not. On arm B the threshold is therefore between 58 and 69 prompt tokens, and
every item in all three benchmarks sits above it except 10 HumanEval items: 1,654 of 1,664 items are in the
diverging regime (1,660 of 1,664 on arm A, where 6 of those 10 also diverge, so arm A's threshold is lower).

## 4. Scores, with the stock grader, a corrected extractor, and the ceiling no extractor can pass

Both runs were re-scored in this session with the same `scripts/quality/quality_score.py` and the stock
`work/QualityCmp/data/items_*.jsonl` gold answers. The stock column reproduces
`work/Int4Window/scores/summary.json` and `work/QualityCmp/scores/summary.json` exactly (143/44, 417/438,
86/87 and 482/484, 759/752, 133/143), so the published tables are a faithful summary of these rows.

| run | bench | INT4 stock | FP4 stock | INT4 corrected | FP4 corrected | INT4 ceiling | FP4 ceiling |
|---|---|---|---|---|---|---|---|
| I4W | gsm8k | 143/500 = 28.6% | 44/500 = 8.8% | 143 = 28.6% | 44 = 8.8% | 210/500 = 42.0% | 59/500 = 11.8% |
| I4W | mmlupro | 417/1000 = 41.7% | 438/1000 = 43.8% | 442 = 44.2% | 453 = 45.3% | n/a | n/a |
| I4W | humaneval | 86/164 = 52.4% | 87/164 = 53.0% | 86 = 52.4% | 87 = 53.0% | n/a | n/a |
| QCMP | gsm8k | 482/500 = 96.4% | 484/500 = 96.8% | 482 = 96.4% | 484 = 96.8% | 487/500 = 97.4% | 486/500 = 97.2% |
| QCMP | mmlupro | 759/1000 = 75.9% | 752/1000 = 75.2% | 789 = 78.9% | 777 = 77.7% | n/a | n/a |
| QCMP | humaneval | 133/164 = 81.1% | 143/164 = 87.2% | 133 = 81.1% | 143 = 87.2% | n/a | n/a |

The corrected GSM8K extractor adds `answer is X` and a trailing `= X` rule after the stock `####` rule; it
changes nothing on either run, because the replies that lack `####` do not contain the gold answer under any
rule (there is 1 unparsed reply on arm A and 35 on arm B, and the ceiling above shows that even a rule that
reads the gold out of the reasoning text cannot pass 42.0 and 11.8 per cent). The corrected MMLU-Pro
extractor adds an explicit `option X` rule before the last-letter fallback and cuts unparsed replies from
137 to 49 (arm A) and 111 to 37 (arm B), worth +2.5 and +1.5 pp. HumanEval is executed, not extracted: the
same reply bodies are run against the official tests, so no extractor applies, and the drop from 81.1 and
87.2 to 52.4 and 53.0 is in the code the model wrote. The failure modes there are not format handling
either: no reply on any arm needed a code fence stripped (0 of 164 on all four), no reply was missing, and
the batch ends only 5 and 6 replies at the cap against 7 and 3 in the earlier run, with 0 and 1 timeouts.

So the extractor is worth 0 to 2.5 pp of a 29 to 68 pp gap (HumanEval 81.1 against 52.4 is 28.7 pp, GSM8K
96.4 against 28.6 is 67.8 pp). `(e)` is a real but small defect in the instrument, and fixing it does not
change a single conclusion.

## 5. The rows that decide it

**(i) Same item, same 1,370-token prompt, same body hash, four arms.** `gsm8k-test-0`, gold 18:

```
QCMP/A (INT4, zmerge8-kfix)  76 tok stop:
  "Janet uses 3 + 4 = <<3+4=7>>7 eggs every day.\nShe sells 16 - 7 = <<16-7=9>>9 eggs at the farmers'
   market.\nShe makes 9 * 2 = $<<9*2=18>>18 every day.\n#### 18"
QCMP/B (FP4, t5-b)          62 tok stop:
  "Janet sells 16 - 3 - 4 = <<16-3-4=9>>9 eggs every day.\nShe makes 9 * 2 = $<<9*2=18>>18 every day
   at the farmers' market.\n#### 18"
I4W/A (INT4, 1ece6e6d+r2+int4)  148 tok stop:
  "Let's break down the problem step by step.\n\n### Step 1: Determine the weight of the box of jelly beans
   \n- Ken buys **2 large pizzas** and **2 small pizzas**.\n- Each large pizza weighs **16 pounds**, and
   each small pizza weighs **8 pounds**.\n- Total weight of jelly beans = $ 2 \times 16 + 2 \times 8 =
   32 + 16 = 48 $ pounds.\n\n### Step 2: Add brownies to triple the weight ..."
I4W/B (FP4, 1ece6e6d+r2)        25 tok stop:
  "Let's break down the problem step by step.\n\n### Step 1: Determine the number of eggs laid per day"
```

The old build answers the Janet question in the prompt's own `<<>>`/`####` format. The new build's INT4 arm
answers the prompt's *eighth few-shot example* (Ken's care package) using the *seventh* example's numbers
(Albert's pizzas), 300 tokens of prompt before the question. Its FP4 arm starts the right question and emits
`<|im_end|>` after 25 tokens with no answer. Neither reply is a truncated version of the old reply.

**(ii) A two-token reply on a 1,346-token prompt, and the engine's own log of it.** `gsm8k-test-6`, arm A:

```
row: prompt_tokens 1346, completion_tokens 2, finish_reason "stop", text "T"
log: [tensorfold] done cmpl-a00ed7b96626549efd119514de1dd619 prompt=1346 cached=2 thinking=False
     effort=none tokens=2 sha=da16b682219d finish=stop rounds=1 accepted=0/1 ttft=1.823 ...
```

This is the only arm A GSM8K row with 1346 prompt tokens and 2 completion tokens, so the log line is that
row. `accepted=0/1` says the speculative draft was rejected, so the token came from the target model's own
argmax after a 1,346-token prefill: the target's argmax was `T`. Under the same body the 2026-11-19 FP4 arm
produced the full four-line solution ending `#### 260`. Stopping is not the cap (`max_tokens` 1024 was not
reached), and it is not the stop string doing something the old build did not do (the same `["<|im_end|>"]`).

**(iii) The replies name the prompt's few-shot example, not the question.** Counted over the reply text,
case-insensitive, for the jelly-beans/care-package example that the prompt contains for every item:

| run | arm | replies naming the jelly-beans example | items whose own question does |
|---|---|---|---|
| I4W | A | 166 of 500 | 1 of 500 |
| I4W | B | 145 of 500 | 1 of 500 |
| QCMP | A | 0 of 500 | 1 of 500 |
| QCMP | B | 1 of 500 | 1 of 500 |

The most frequent single reply in arm B appears 31 times, always the same string:

```
31x "Let's break down the problem step by step."
23x "Let's break down the problem step by step.\n\n1. **Initial Weight of Jelly Beans:**\n   - Ken ..."
20x "Let's break down the problem step by step.\n\n1. **Initial Weight of Jelly Beans:**\n   - The ..."
```

and in arm A the top three (4, 3 and 2 occurrences) all begin `### Step 1: Determine the weight of the box
of jelly beans`. Thirty-one identical replies to thirty-one different questions is the model continuing the
prompt's last example instead of the question that follows it.

**(iv) The MMLU-Pro option letters stop matching the options that were sent.** `mmlupro-test-2039`, 167
prompt tokens, gold `I`. The harness sent exactly this list:

```
A. No mode   B. 6, 7, and 8   C. 7 only   D. 6 and 9   E. 6 and 8
F. 6, 7, and 3   G. 5 and 9   H. 3 only   I. 3 and 7   J. 8 and 9
```

```
QCMP/A  recites A..J exactly as sent, then: "The correct modes are 3 and 7, which corresponds to option I.
        The answer is I."                                    (correct)
I4W/A   recites: "- A. No mode\n- B. 6, 7, and 8\n- C. 7 only\n- D. 6 and 9\n- E. 6 and 8\n- F. 3 and 7
        \n- G. 5 and 9\n- H. 3 only\n- I. 3 and 9\n\nThe correct option is **F**. The answer is F"
        (F is not "3 and 7"; the sent F is "6, 7, and 3", and the sent I is "3 and 7", which the reply has
        moved to F and re-invented as "3 and 9" at I)
```

Counted over all 1,000 items: among replies that recite at least five option lines (503, 510, 548 and 558
of 1,000 respectively), the share of recited letters whose text matches the option actually sent at that
letter is

```
QCMP/A 4105/4971 = 82.6%      QCMP/B 4174/5057 = 82.5%
I4W/A  3506/6857 = 51.1%      I4W/B  3971/7235 = 54.9%
```

The new build's option letters are mis-associated roughly three times as often. That is the model reading a
prompt it did not receive.

**(v) A near-identical divergence, to show the defect is in the prompt-side representation and not in
"sampling".** `HumanEval/155`, 69 prompt tokens, arm B: the first 66 tokens of code are identical
(`even_count = 0 ... return (even_count, odd_count)`), then the old build emits `<|im_end|>` and the new
build continues for 1,024 tokens writing asserts about its own function. `HumanEval/16`, same band, differs
by one trailing newline. Greedy output that agrees for 66 tokens and then disagrees at the stop decision is
a computation that is *almost* right, not a different sampler: and it cannot be a sampler at all, because
the same build reproduces the reference build's text byte for byte, with `sampling: greedy` recorded on both
sides, on all 10 HumanEval prompts of 43 to 58 tokens (arm B) and on all six 22 to 28 token golden cells
(arm A). The divergence appears only above that length, and only in proportion to it.

**(vi) The fault reproduces at one request at a time, deterministically.** `quality_probe_thinking.py` sends
the first GSM8K prompt to `/v1/completions` on its own, before any benchmark traffic, with `temperature: 0`,
the prompt's own `stop`, and `max_tokens: 256` instead of the benchmark's 1024. On both arms the probe's
reply is byte-identical to the reply the concurrent benchmark run produced later:

```
arm A  probe 2026-11-21T21:47:46Z, 470 chars   batch started 1795297669.38, 3.4 s later; row 470 chars, 148 tok
       row.startswith(prefix) True, common prefix 470 of 470
arm B  probe 2026-11-21T23:46:01Z,  97 chars   batch started 1795304762.68, 1.7 s later; row 97 chars, 25 tok
       row.startswith(prefix) True, common prefix 97 of 97, identical tail including the final token
```

The probe's smaller cap never applied (148 and 25 tokens, both well under 256), and both replies finished
with `finish_reason: stop`, so this is the complete text, not a shared opening. The two requests are seconds
apart on the same boot, and the only thing that changes between them is whether other streams are in flight:
the probe is alone, the row is inside a four-way concurrent run. They produce the same wrong answer
character for character. That rules out cross-stream KV contamination, batch-width numerics and load as
necessary conditions, and it means the fault is inside a single request's own prompt and decode path. It
also means this window could have caught the defect before spending the GPU time: one probe request per arm,
compared against a reference build, would have failed it at 21:47:46.

## 6. Ruling the candidates in and out

| candidate | verdict | the evidence |
|---|---|---|
| (a) `max_tokens` too small | out | `max_tokens` is 1024/1536/1024 in all four combinations, in the hashed body; truncation counts are 49/20 (I4W) against 3/2 (QCMP) on GSM8K, so the *new* build hits the cap more, not earlier, and the median new-build reply is 34 tokens |
| (b) a `stop` sequence firing early | out | the stop lists are byte-identical (`["<\|im_end\|>"]` and the five HumanEval strings); a stop string cannot fire at 34 tokens here and at 127 tokens there on the same list; `finish_reason: stop` is the model emitting the end token |
| (c) prompt rendered differently | out | `prompt_sha256` and `body_sha256` equal on 1,664 of 1,664 items across all four run/arm pairs, prompt files byte-identical, `prompt_tokens` identical item by item |
| (d) the model answering differently because of a setting | **in** | the remaining variables are the engine image on both arms, plus two INT4 patches arm A needs and, for arm A only, four serve flags (section 1). Checkpoints, client and bodies are equal. This is the cause |
| (e) the grader's extraction | partly in, not the cause | corrected extractor: GSM8K +0.0 pp, MMLU-Pro +2.5/+1.5 pp, HumanEval not an extractor (executed). The GSM8K ceiling of 42.0/11.8 pp against 97.4/97.2 rules out any extractor |

Within (d), the evidence narrows it to the prompt-side path rather than decoding or sampling: on arm B,
prompts of 58 tokens or fewer reproduce the reference build exactly (greedy, drafts on, byte-identical
text), prompts above that diverge, the divergence grows with prompt length, and the observable failures are
failures to use the prompt (wrong example answered, option letters re-associated, question not reached).

The build also records the closest thing to a mechanism in its own boot log, on both arms:

```
info: flashnext: window self-check: 1176 of 2080 rows byte-equal to their one-token steps (widths 1-64)
warning: flashnext: width 49 is the first with rows differing from their one-token steps
info: flashnext: widths 1-48 are row-equal at every row; serving 48-row copy windows
warning: flashnext: serving 48-row copy windows after the self-check
```

1,176 is the sum of widths 1 to 48 and 2,080 is the sum of widths 1 to 64, so this says: every width up to
48 rows is exactly what a one-token-at-a-time pass produces, every width from 49 to 64 is not, and the build
ships anyway with the window capped at 48. That is a recorded, unresolved correctness hole in this build's
batched forward path. It is **not proven** to be the same hole that corrupts the long prompts here (prefill
runs in passes of up to 3,072 rows, which is a different path from the decode copy window), so treat it as
the leading lead for whoever owns the engine, not as the diagnosis: the diagnosis is the measured output
behaviour in sections 3, 4 and 5, which stands on its own whatever the mechanism turns out to be.

Two candidate mechanisms are worth naming for the owner of the build, and both are cheap to bisect:

1. **The prompt path** (chunked or windowed prefill, or the KV page mapping when a prompt spans pages). The
   evidence for it is the shape of the failure: faithful below 58 prompt tokens, wrong above, worse the
   longer the prompt, wrong in the direction of *using the wrong part of the prompt*, and present in a single
   request with no other stream in flight (section 5(vi)).
2. **Speculative acceptance.** All three arms that produced rows here serve with `drafts: MTP + copies`, so
   speculation is not itself the difference, but the *drafter* is built differently: the new arms log
   `the drafter's BF16 linears kept as mxfp8 (TF_FLASHNEXT_MTP_WEIGHTS)` and register
   `TF_FLASHNEXT_KV_PAGES=4096`, and the 2026-11-19 run captured no environment for its arms at all (its only
   record is `registered overrides: none`), so whether its draft depth and confidence knobs matched is
   unknown rather than equal. A verifier that accepts a draft token the target did not choose would corrupt
   text in a length-dependent way too. Testable in one boot: store the drafter as it ships (drop
   `TF_FLASHNEXT_MTP_WEIGHTS`), or turn drafts off, and re-run the 20 item fidelity gate; if the text becomes
   the reference build's, the defect is in acceptance and not in prefill.

## 7. The verdict, and the re-run it forces

**Not salvageable as scored. Not salvageable by re-scoring.**

- Re-scoring cannot help: the GSM8K ceiling (the reply contains the gold number anywhere at all) is 42.0%
  for INT4 and 11.8% for FP4 against 97.4% and 97.2% in the earlier run, and MMLU-Pro extraction is worth
  2.5 pp of a 32 pp gap.
- Filtering cannot help: only 10 of 1,664 items sit in the prompt-length band where this build reproduces
  the old build, and on arm A 6 of those 10 also diverge.
- What is left is a re-run of **all 1,664 items on both arms** (GSM8K 500, MMLU-Pro 1,000, HumanEval 164),
  with the same bodies, the same prompts, the same checkpoints, on an engine build that first passes a
  prompt-fidelity gate, and, for the INT4 arm, with production's own INT4 flags as well as the window's, so
  that the image is the only variable on both arms (section 1).

The gate the re-run must pass before its quality numbers mean anything, stated so it can be mechanised:
take 20 items spanning the three benchmarks with prompts above 512 tokens, replay them on the new build and
on a reference build that is trusted (`zmerge8-kfix-e5139fcd8c6101c7` for INT4, `t5-b-c0eb2126` for FP4),
greedy, with the same serve flags on both sides so the image is the only variable, and require identical
`text_sha256` on all 20. If they differ, the build is not eligible for a quality A/B and the failure is an
engine bug report, not a quality result. A cheaper proxy that would have caught this window in one command:
require the option-recitation match rate of section 5(iv) to be within a few points of the reference build's
82.5%, and fail the window below 75%.

Do not repeat the window's own `SANITY ok` check as the gate. That probe is a 16 token chat request, it
returns `OK.` on arm A and `OK` on arm B while both arms record it as a pass, and it is below the length at
which this build stops being faithful. A gate that both a working and a broken build pass, and that differs
between the two arms of the same window, detects nothing.

## 8. What a corrected comparison could claim at this n

The window's design is sound and worth re-running as it stands: 1,664 items, paired by id, the same bodies
on both arms, engine-matched, and a 20-patch tree shared by both arms so the difference is the checkpoint
plus the two INT4 patches arm A needs. At n = 500 (GSM8K), 1,000 (MMLU-Pro) and 164 (HumanEval), with the
discordant-pair counts these two runs actually produced (143, 287 and 49), an exact two-sided McNemar test at
alpha 0.05 reaches 80 percent power only for a net advantage of 34 items (6.8 pp of the benchmark) on GSM8K,
48 items (4.8 pp) on MMLU-Pro and 19 items (11.8 pp) on HumanEval, and its power for a 5 pp difference is 54
percent, 83 percent and 20 percent respectively. Recomputed here from the discordant counts in
`scores/summary.json`; `ANALYSIS.md` records 34, 49 and 20 items, 6.8, 4.9 and 12.2 pp, and 54, 83 and 19
percent from the same counts, so the two instruments agree to within a rounding step.

So a corrected run of this size could say: "FP4 is not more than about 7 pp better than INT4 on GSM8K at the
levels both reach (96.4 and 96.8 on 2026-11-19, a 0.4 pp difference, would be excluded by a wide margin)",
and "an FP4 advantage of 5 pp or more on MMLU-Pro would have been detected with 83 percent power, and was
not". It could not say anything useful about HumanEval beyond an 11.8 pp resolution, where 19 of 164 items
is the whole resolving power of the benchmark at this n, and it could not attribute a difference to the
checkpoint alone while arm A carries two patches arm B does not: that needs a third arm, FP4 built with
patches 0021-0022, or an INT4 arm without them. What it could never do is produce the kind of number the
current window reports (a 20 pp GSM8K gap, p below 1e-6) from a working build: on the build where both
checkpoints are known good, that gap is 0.4 pp with p = 0.73.

## 9. Where every number comes from

| table or claim | source |
|---|---|
| request fields, body hashes, prompt hashes, prompt token distributions | `work/Int4Window/box/out/arms/{A,B}/raw/*.jsonl`, `work/QualityCmp/box/out/raw/*/*.jsonl`, `stage/in/prompts/*.jsonl`, `work/QualityCmp/prompts/*.jsonl`; script `work/Int4Window/diag/tabulate.py` |
| reconstructed `body_sha256` | `work/Int4Window/diag/` inline run over `prompts_gsm8k.jsonl`, quoted above |
| reply shapes (section 2) | same raw rows; `work/Int4Window/diag/tabulate.py` |
| divergence by prompt length (section 3) | same raw rows; `work/Int4Window/diag/diverge.py`, `work/Int4Window/diag/natural.py`, `work/Int4Window/diag/shortpairs.py` |
| golden cells | `work/Int4Window/box/out/P/golden.json`, `work/Int4Window/box/out/arms/A1/golden.json`, `work/Int4Window/box/out/arms/A/sanity.json` |
| scores, stock and corrected, and the ceilings | `scripts/quality/quality_score.py --raw <run> --out work/Int4Window/diag/rescore-stock-{i4w,qcmp}`; corrected extractor `work/Int4Window/diag/corrected.py` |
| example and option contamination (section 5 iii, iv) | raw rows plus `prompts_gsm8k.jsonl`, `prompts_mmlupro.jsonl`; `work/Int4Window/diag/options.py` |
| engine log lines | `work/Int4Window/box/out/arms/{A,B}/server.log` |
| checkpoints, flags, images | `work/Int4Window/box/out/{IDENTITY-A,IDENTITY-B,cmd.txt}`-adjacent files, `arms/*/cmd.txt`, `arms/*/env.txt`, `work/QualityCmp/out/{A,B}/provenance.txt`, `work/QualityCmp/out/B/boot.log` |
| detectable difference and power | `work/Int4Window/diag/mde.py` (exact binomial power over the discordant counts in `scores/summary.json`) |
| the earlier run's published numbers | `work/QualityCmp/scores/summary.md`, `work/QualityCmp/scores-recheck/summary.md` (an independent re-score that reproduces it exactly), `docs/QUALITY-A-VS-B-2026-11-18.md` |

Nothing in this document is inferred where a file was available to read. The one labelled inference is the
mechanism behind section 6's self-check warning, which is stated as a lead, not a cause.
