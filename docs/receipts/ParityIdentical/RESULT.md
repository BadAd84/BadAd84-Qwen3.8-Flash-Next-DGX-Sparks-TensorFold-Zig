# Why the two engines return different greedy replies: state at hand-off

P is production (`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`), D is the dev composition
(`tensorfold-qwen38:r5dev40`), one checkpoint, one greedy request shape. This receipt carries the part of the
attribution that is finished - the numeric-path inventory, the pre-window measurements taken from the recorded
artefacts, the localisation window and its decision rules - and states plainly what the window has not yet measured.

## What is finished

1. **The numeric-path inventory**, `INVENTORY.md`. Every place the two arms can round or order arithmetic
   differently, with file:line and the effective value on each arm: the weight path (same GPTQ int4 coding, same
   `fn_int4.cu` arithmetic contract, the same four int4 settings in force), the drafter (different 8-bit codings and
   policies, but an exact-match acceptor that emits the target's own pick, and near-identical draft volume in
   practice), attention and KV (the same fp8 e4m3 row format and scale rule, different kernels and reduction
   structures), the reduction structure (R1-R7), and the sampler (argmax with the same lowest-id tie-break at
   temperature 0, `top_p` inert). Nine candidates ranked; nine refuted with evidence.

2. **The pre-window measurements**, every one from artefacts already on disk:

   | measurement | result | source |
   |---|---|---|
   | prompt rendering, same ids on both arms | 12 of 12 rows equal at C=1, 48 of 48 at C=8 (`prompt_tokens` per (`kind`,`pass`,`j`)) | `docs/receipts/ParityAB/ev.tgz`, `dec.jsonl` |
   | each arm deterministic against itself across two fresh boots | P 6/6 at C=1, 12/12 at C=2, 24/24 at C=4, 36/36 at C=6; D 6/6, 12/12, 24/24 (C=6 and C=8 have one boot each) | `ev/{P,D}/c*/run{1,2}/dec.jsonl` |
   | the same six golden replies on both arms | 6/6 identical, including a 215- and a 256-token reply (497 tokens in all) | `ev/{P,D}/c1/run2/gold.txt` |
   | the divergence is a rare per-token event, not a gross difference | prose: 0 of 63 rows equal -> a flip at least every 157 tokens (95%); code: 10 of 63 equal -> a flip about every 262 tokens; the golden set is consistent with a flip rate at most ~1 in 300 | `flip-rates.txt` |
   | the divergence is prompt-dependent | at C=8, code prompt 0 agrees 3/6, prompt 3 1/6, prompt 1 1/6, prompt 2 0/6; every prose prompt 0/6 | `ev/{P,D}/c8/run1/dec.jsonl` |
   | draft volume is nearly the same on both arms | drafted a round, prose: P 2.18-2.38, D 1.91-2.21; code: P 5.02-5.92, D 4.84-6.13 (C=1..8) | `INVENTORY.md` section 2 |

   Together these fix the frame: the engines' model inputs are identical, each engine is reproducible, they agree on
   the factual golden prompts, and they disagree on the open-ended prompts at a rate of roughly one token in 150-300
   - the signature of a near-tie decided at a margin of a fraction of a logit, not of a gross arithmetic fault.

3. **The localisation window**, `window.sh` + `in/` + `boot_cell.sh`, deployed on spark6 at `~/work/parityid` and
   **queued** on `~/work/gpu.lock` behind the ParityGap lane (its own log: `run-queued.log`; flock pid 2678319,
   queued 18:43:04Z). It runs, detached, with the production restore in an EXIT trap:

   - cells at C=1: P and D controls twice each (determinism), the second boot of each arm carrying the distribution
     probes;
   - cells at C=8: the same four boots;
   - one boot each for the ranked arms: `DRAFTS=0` on both arms, `PROMPT_MM=0` on P, `CHUNK=2048` on D (solo and
     busy), `KV_DTYPE=bf16` on both, `LEARN=0` on D, `VISION=0` on P, `INT4_TILE=64` on both (the tile-plan
     sensitivity probe; `HEAD_ROW_TILES` cannot serve as one because both launchers pin it to 2 in their own exec
     env, `~/qwen6-start.sh:87` and `~/qwen6-start-prod.sh:54`, which the dry-run preflight caught - the arm would
     have been null), `MTP_WEIGHTS=bf16` on D, plus C=8 for the two drafter arms and the chunk arm;
   - five fixed prompts, byte-identical on both arms: the ParityAB pass-0 prose and code requests verbatim (the
     reproduction control, against `in/recorded-shas.json`) plus about 1k prose, about 1k code and about 8k prose;
   - greedy, 512 tokens, thinking off; per reply the client text sha, the engine token hash, the reconstructed token
     ids and the stream's per-token deltas, so the first divergent token index and its token text are known;
   - the request shape of stage 2 is verified in the engines' own code: a raw prompt skips the chat template and still
     resolves the request's sampler on both arms (`P:.../server/chat.zig:155,173`; `D:.../server/chat.zig:158,182`), and the
     keyed draw is the same expression on both arms, so the same seed is the same experiment twice;
   - stage 2 at the first divergent token: a temperature-0 control that must reproduce each arm's own next token,
     then temperature sweeps at T = 1.0, 0.2, 0.05, 0.01 with 60 distinct seeds each at a token-id prompt on
     `/v1/completions` (neither engine serves logprobs for this family: P refuses them in `server/fields.zig:287`,
     D's Flash Next backend registers no `first_row`), which measures the bf16-quantised margin that decides a
     greedy argmax; because the draws are paired, the summary also reports the seeds on which the two arms pick
     different tokens at each temperature.

4. **The decision rules**, `METHOD.md`, written before the data: what each determinism, first-token and margin
   measurement would mean, and what makes a lever load-bearing or refuted.

5. **A dry-run preflight of every cell's boot environment**, `preflight-dryrun.txt`: 12 of 14 modes went through
   their recipe's own DRY_RUN argument check with the parser accepting the arguments (the other two were refused by
   the recipe's state lock because a serve was starting at that moment; their wiring is proved by the identical
   forwarding path that passed and by the engines' readers). It caught one null arm, `HEAD_ROW_TILES` - pinned to 2
   by both launchers - which the window now runs as `INT4_TILE=64` instead.

## What the window has not measured yet

No cell has run: the lock is held by the ParityGap lane (four of its processes alive at hand-off, production up and
`/health` 200). Nothing in this receipt claims a first divergent token, a margin, or a lever verdict; those arrive
with the window's cells.

## Retrieving and scoring the window when it finishes

The window writes every intermediate result to disk as it goes (`~/work/parityid/out/<label>/c<C>/rows.jsonl`, plus
`plan.txt`, `env.txt`, `cmd.json`, `logprobs.txt`, `boot.log` per boot, and `dist/*.jsonl`). The watcher
(`work/ParityIdentical/watch.sh`, running as the workstation job `bg_2108`) waits for `EXIT-DONE`, packs
`~/work/parityid/parityid-ev.tgz` and copies it to `work/ParityIdentical/ev-window.tgz`. Then, from the unpacked
tree:

```
python3 docs/receipts/ParityIdentical/in/analyse.py report --root <ev>/out --md report.md --json report.json
python3 docs/receipts/ParityIdentical/in/analyse.py distsum --root <ev>/out --md dist.md
python3 docs/receipts/ParityIdentical/in/summarise.py --root <ev>/out \
    --recorded docs/receipts/ParityIdentical/in/recorded-shas.json --md tables.md
```

`summarise.py` prints the reproduction verdict (P's and D's prose-rec0/code-rec0 shas against
`20657973...`/`7f3dc331...` and `45f424ba...`/`3307e726...`), the per-cell divergence, and each lever against its
own control and against the other arm. The acceptance items that land with it: the determinism result per arm; the
first divergent token index per prompt and level; the margin at that step with its control; and at least one lever
measured on/off against both arms - named as the mechanism if it removes the divergence, or as load-bearing if it
moves the arm's own replies, or refuted with its numbers.

The restore proof is the window's own `RESTORED` line (health 200, the pinned image id, and
`check-prod-env.py --inspect` at 0 problems), written by the EXIT trap whether the run succeeds or fails, with an
outer re-check that re-queues and restores again if `/health` is not 200 after the lock is released.

## Files

- `INVENTORY.md` - the numeric-path inventory, with file:line and values, ranked and with refutations.
- `METHOD.md` - the decision rules.
- `flip-rates.txt` - the recorded window's row-equality and per-token flip scale, prompt-kind by prompt-kind.
- `window.sh`, `boot_cell.sh`, `in/` - the window and its harness (prompts, probes, analysis, summariser, the two
  env files, the production restore check), `in/recorded-shas.json` the reproduction targets.
- `run-queued.log` - the window's log at hand-off.
