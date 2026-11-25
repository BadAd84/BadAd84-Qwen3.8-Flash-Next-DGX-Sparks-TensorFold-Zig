# The window's decision rules (drafted before the data landed)

These rules name, in advance, what each measurement would mean, so the verdicts in RESULT.md are not fitted
after the fact.

## Determinism (step 1)

`P_a` against `P_b` and `D_a` against `D_b`, two fresh boots each, at C=1 and C=8, five prompts. A row is
"self-equal" when both the client text sha and the engine token sha agree.

- Every row self-equal on both arms: each arm is deterministic against itself, and every cross-arm difference is a
  reproducible engine difference. The window proceeds.
- Any row self-unequal: that arm is not deterministic at that level, which is the finding, and no cross-arm
  attribution is read from that cell.

## The first divergent token (step 2)

Per (prompt, level, j): the first character where the two texts differ, and the first token index where their
reconstructed ids (and the stream's per-token deltas) differ.

- Token 0 (or the first generated token): divergence originates in the prompt pass / the last prompt row's logits -
  the prefill path, the attention over the prompt, the head.
- A later index k: the divergence originates in the decode loop, after k tokens agreed; the step that flipped is at
  index k, so everything that differs in the decode path is a candidate and the prompt-pass levers cannot be the
  mechanism for that row.

## The gap at the divergent step (step 3)

Instrument: the forced prefix (chat prompt ids + the reply's ids up to k) as a token-id prompt on
`/v1/completions`, `max_tokens` 1, and (a) a temperature-0 control that must reproduce the arm's own next token, then
(b) temperature sweeps at T = 1.0, 0.2, 0.05 and 0.01 with 60 distinct seeds each, `top_k` 20, `top_p` 1, `min_p` 0.
`n(P)` and `n(D)` count the two arms' divergent tokens among the samples; `gap = ln((n(P)+0.5)/(n(D)+0.5))` at that
T, and `logit gap = gap x T`.

The sampler ranks the engine's **bf16** logits (both arms' heads write bf16 and both argmaxes read that row), so the
quantity the sweeps measure is the bf16-quantised margin, which is exactly the margin that decides a greedy argmax:

- `control_ok` false on either arm: the forced prefix is not the chat prompt's own continuation (or the route
  refuses the shape), the sweep's numbers are void, and RESULT.md says so with the recorded error. The bisection
  stands on its own.
- |logit gap| < 0.02 in both arms: the two arms' bf16 logits at that position are **equal**; a tie alone cannot
  explain different winners (both tie-break to the lowest id), so the divergence must be earlier than k or in the
  prefix reconstruction - the row is reported as an instrument mismatch, not as a mechanism.
- 0.02 <= |logit gap| <= 0.25: a margin of one to four bf16 steps at a logit near 10 - a near-tie decided by a
  summation-order-scale difference between the engines.
- |logit gap| > 0.5: a margin far larger than any fp32 summation-order difference; that is arithmetic, not a tie.

## The levers (step 4)

Each lever is one fresh boot of one arm with one setting moved, against that arm's control on the same five prompts
at C=1 (C=8 for the two drafter arms and the chunk arm). Two comparisons per lever:

- **against its own control**: if the arm's own replies change, the setting is numerically load-bearing on these
  prompts, and since the other arm runs a different value of that same setting, the setting is a sufficient
  explanation of the cross-arm difference.
- **against the other arm's control**: if the arms now agree, the setting is the mechanism (the smallest change that
  removes the divergence).

A lever that changes nothing in its own arm is refuted for these prompts, with its numbers.

## The mechanism statement

RESULT.md names one mechanism only when it has (a) the first divergent index, (b) the measured margin at that index,
and (c) at least one lever that either reproduces the divergence within an arm (load-bearing) or removes it across
arms. Everything else is reported as measured and refuted, with its numbers.
