# Parity-gap window: intermediate results (C=1 screen only)

Written while the window runs, from `work/ParityGap/partial/` (cells copied off spark6 at 18:23Z; the
window's own `out/run.log` is authoritative). Driver `driver/window2.sh`, arms defined in
`driver/boot_env2.sh`, scorer `driver/score_arms.py`.

Status at this copy: 4 of the 6 screen cells at C=1 complete (P, A1, A3, D), A2 booting, A4 and the C=8
pass still to run. All armchecks OK so far: A1 carries the five `TENSORFOLD_COPY_*` names and its boot
prints `copy policy: miss keep, ramp jump, shared rounds ramp prompt copies, resync prompt copies`; A3
carries `TF_FLASHNEXT_GRAPH_FAIL=1` and its boot prints `graph warm-up: 0 graphs on 8 pooled sequences`
(against P's 384), which is the eager path proved, not asserted.

## C=1, decode (aggregate tok/s, median of 3 passes) and the per-round decomposition

| arm | prose | vs P | vs D | code | vs P | vs D | tok/round prose | code | rounds/s prose | code | ms/round prose | code |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 73.5 | 1.000 | 1.076 | 116.1 | 1.000 | 1.006 | 2.48 | 5.55 | 27.64 | 21.31 | 36.18 | 46.92 |
| D | 68.3 | 0.929 | 1.000 | 115.4 | 0.994 | 1.000 | 2.58 | 5.89 | 24.86 | 19.40 | 40.23 | 51.54 |
| A1 | 66.4 | 0.903 | 0.972 | 115.5 | 0.995 | 1.001 | 2.58 | 5.89 | 24.12 | 19.39 | 41.46 | 51.57 |
| A3 | 73.3 | 0.997 | 1.073 | 115.4 | 0.994 | 1.000 | 2.48 | 5.55 | 27.50 | 21.33 | 36.36 | 46.88 |

Reading: at one stream the deficit is a per-round cost, not drafting. D submits 4 to 6 percent MORE tokens
a round than P (2.58 against 2.48 prose, 5.89 against 5.55 code) and is still slower, because its round
takes 11.2 percent longer on prose (40.23 against 36.18 ms) and 9.8 percent longer on code (51.54 against
46.92). So any lever framed as "D drafts less deeply" is refuted at this level by the engine's own
`drafted`/`rounds` counters: D drafts more.

- A3 (P, graphs eager) is P to within 0.3 percent decode and byte-identical (6/6 reply hashes): the
  captured graphs are worth nothing at one stream, so they cannot explain the one-stream prose gap.
- A1 (D, production's copy policy under the dev names) is byte-identical to D (6/6 hashes) and moves
  decode by -2.8 percent prose / +0.1 code: at one stream the copy policy is level to slightly negative,
  and the copy levers cannot explain the one-stream prose gap either.
- A1's cold TTFT (2.941 s at 8k, 11.756 s at 32k) sits at D's level (D's own TTFT not yet captured in
  this copy), as expected: the copy policy acts on copy rounds, not on prefill.


## The C=1 deficit is stable across passes, and it is per round

The three decode passes per cell, same prompts, same order (`dec.log` per cell):

| arm | prose pass0 / pass1 / pass2 | code pass0 / pass1 / pass2 |
|---|---|---|
| P | 75.0 / 73.5 / 59.5 (tokens 512/512/419) | 128.9 / 116.1 / 115.8 |
| D | 71.6 / 68.3 / 55.1 (tokens 512/512/418) | 117.9 / 115.4 / 115.2 |

Pass by pass, P against D: prose 0.955, 0.929, 0.926; code 0.915, 0.994, 0.995. The third prose
pass is a slow outlier on both arms (the reply ends at 419/418 tokens), and the median of the three picks
pass1 on both, so the median is not selecting a lucky pass. Code at one stream is equal on two of three
passes; the first pass alone favours P.

Per round, from the same lines (pass1 each): P prose 512 tokens in 6.96 s over 194 rounds = 35.9 ms a
round with 2.64 tokens; D prose 7.49 s over 189 rounds = 39.6 ms with 2.71 tokens (round +10.4 percent,
tokens +2.6). P code 4.41 s over 98 rounds = 45.0 ms with 5.22 tokens; D 4.44 s over 88 rounds = 50.4 ms
with 5.82 tokens (round +12.0 percent, tokens +11.5). So on code D's deeper chains (its `drafted`/`rounds`
counters) pay for the slower round exactly; on prose the chains are the same length and the slower round
is a pure loss. Prose is where the one-stream deficit lives, and it is not drafting.

## C=1, cold TTFT (median of 2, idle)

| arm | cold1k-off | cold8k-off | cold8k-on | cold32k-off | cold32k-on | warm2k |
|---|---:|---:|---:|---:|---:|---:|
| P | 0.412 | 2.633 | 2.647 | 10.487 | 10.505 | 1.210 |
| D | 0.489 | 2.929 | 2.931 | 11.795 | 11.738 | 1.195 |
| A1 | 0.487 | 2.941 | 2.952 | 11.756 | 11.732 | 1.167 |
| A2 | 0.439 | 2.951 | 2.978 | 11.918 | 11.928 | 1.247 |
| A3 | 0.398 | 2.580 | 2.625 | 10.521 | 10.526 | 1.103 |

D against P at C=1: 1.112 (8k-off), 1.125 (32k-off). A2 is P with the captured prompt-matmul path
turned off (`TF_FLASHNEXT_PROMPT_MM=0`; boot line `matmul K slices split with _reduce`, 6/6 reply hashes
equal to P, decode identical to P to 0.1 percent): its cold TTFT reads 1.121 (8k-off), 1.136 (32k-off),
1.125/1.136 (thinking on) against P. **Turning the captured prompt-matmul path off on P reproduces the
whole cold-prefill gap D shows** (1.112/1.125), byte for byte on replies and with decode untouched. The
1k control cell (+6.6 percent) carries the same sign and a smaller size, as a size-dependent prefill
throughput effect should.

P reproduces the recorded window: cold8k 2.633 against 2.588 then, cold32k 10.487 against 10.490, prose
73.5 against 71.8, code 116.1 against 115.4. The cross-window control is intact, so the arm ratios in
this window are readable against the recorded D/P table.

## Open at this point

A2's cold TTFT (P with the captured prompt-matmul path off) is the prefill test and had not run in this
copy; A4 and the C=8 screen, then the confirm pass, follow. This file is superseded by `RESULTS.md` when
the window writes `WINDOW-DONE`.
