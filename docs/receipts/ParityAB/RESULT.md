# Parity window: r5dev40 against production at 1, 2, 4, 6 and 8 streams

## What ran

One hold of spark6's `~/work/gpu.lock`, driver `window.sh` in this directory, one fresh boot a level each,
interleaved (C=1 and C=4 P then D; C=2, C=6 and C=8 D then P), then one rerun pass over all five levels because
the first pass's spread check fired. Decode: `tfm_decode_ids.py` (the target's own harness plus the engine's
per-reply token hash), C barrier-started greedy requests, 512 tokens, three passes, thinking off, prose and
code prompts with a per-pass nonce. TTFT: `ttft.py`, cold 1k, 8k and 32k, thinking off and on, two reps, idle,
plus the warm agent turn (a kept 100k conversation plus 2k new tokens). Golden 6/6 before every cell's probes.

| arm | image | engine | environment | checkpoint |
|---|---|---|---|---|
| P | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea77ee` | the release plus our 0001-0028, the zmerge8 keep set and two kindling boot fixes | its own launcher, 54-name environment, vision on | azampatti INT4-AutoRound `14642741` |
| D | `tensorfold-qwen38:r5dev40` `sha256:adc40fe3ea7b` | upstream main `1ece6e6d` plus the 40 patches of `patches/main-1ece6e6db-r5-dev` | the dev launcher with `dev.env`, vision off, the persistent KV tier | the same checkpoint |

The checkpoint is the same on both arms, proven from the production container's own command, both arms' rendered
argv and every boot's `meta` record (both name `snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd`). So every
cell is engine plus environment, not checkpoint.

Preflight used the served binary and its argument parser as oracles: P's 54 names resolve 53 in its engine binary
(the 54th is the vision helper's), D's 114-name env resolves 101 with the 13 named, every launch flag goes
through the binary (P 12 accepted plus 3 dependency-gated; D 16 accepted), and both arms' full argvs are accepted.

## Result: the composition does not replace production

Decode, aggregate tokens a second, median of three passes:

| concurrency | P prose | D prose | D/P | P code | D code | D/P |
|---:|---|---|---:|---|---|---:|
| 1 | 71.8 | 65.6 | 0.914 | 115.4 | 113.5 | 0.984 |
| 2 | 105.6 | 100.0 | 0.947 | 176.1 | 169.5 | 0.963 |
| 4 | 165.2 | 155.8 | 0.943 | 258.1 | 239.5 | 0.928 |
| 6 | 206.6 | 185.9 | 0.900 | 314.2 | 282.8 | 0.900 |
| 8 | 239.2 | 214.0 | 0.895 | 380.8 | 326.7 | 0.858 |

D against P over the ten aggregate cells: geometric mean **0.922**; it is slower at every level, and the loss grows
with concurrency (about 2 percent at one stream on code, 10 to 14 percent at eight). Production itself tracks the
recorded target (`docs/SPEED-TARGET-1.2.6.md`) at geometric mean 1.017, so the comparison is against the target
rather than a mis-set baseline.

Cold TTFT, D/P (seconds, median of two reps, idle). 8k and 32k are tight across all five levels; 1k is not usable
(see the spreads):

| case | 1 | 2 | 4 | 6 | 8 |
|---|---|---|---|---|---|
| cold8k-off | 1.141 | 1.141 | 1.109 | 1.180 | 1.175 |
| cold8k-on | 1.115 | 1.123 | 1.125 | 1.170 | 1.149 |
| cold32k-off | 1.125 | 1.126 | 1.119 | 1.127 | 1.115 |
| cold32k-on | 1.113 | 1.118 | 1.121 | 1.122 | 1.115 |
| cold1k-off | 1.253 | 1.302 | 1.317 | 1.552 | 1.555 |

The warm agent turn is 1.015 to 1.125 (both arms report cached tokens on both reps at every level), and the boot is
149 to 152 s for D against 82 to 88 s for P.

## What the window itself says about its numbers

The rerun rule fired on 9 cells after the first pass and on 10 after the rerun, so 8 of 10 cells stay over the
R1/R4 band: decode spreads of 5 to 29 percent and TTFT spreads of 11 to 55 percent. Three consequences:

- The decode medians are the median of three passes, and the two boots per cell agree within 0.984 to 1.038 on the
  aggregate, so the direction of the decode result is not an artefact of the spread. The size of the loss (about 8
  percent geomean) is.
- The cold-1k column is not usable as a verdict at any level: its own spread is 21 to 55 percent while the D/P
  ratio moves from 1.25 to 1.56.
- The 8k and 32k cold-TTFT regressions are consistent across all five levels and both thinking modes, and one cell
  was re-measured directly from the raw `ttft.out` (P 10.45 to 10.52 s, D 11.75 to 11.90 s at 32k), so the
  11 to 18 percent prefill loss stands while its exact size carries the spread.

The rerun's per-cell numbers are in `tables.md` sections "Declared repeats and the rerun rule" and "Boot to boot".

## Replies are not equal between the arms

Both arms are greedy at temperature 0 on the same checkpoint and prompts. At the same prompt, the reply text hash
is equal on 0 of 3 rows at one stream, 0 of 6 at two, 2 of 12 at four, 3 of 18 at six and 5 of 24 at eight (the
engine token hash agrees row for row with the text hash). The engines therefore diverge numerically on a minority
to all of the prompts depending on the level; that is a behaviour change an engine replacement would carry, and it
is separate from the speed verdict above.

## Restoration

The window restored production itself: `RESTORED health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
sha256:235211ea77ee...`, and the box's own gate then read `54 settings, 54 equal, 0 problem(s)`. Re-checked after
the window from this repo's kind-driven gate on a fresh inspect: `prod-env: 117 rows compared (54 carried, 63
pinned; 118 in the file, 1 skipped), 54 in the container, 54 equal, 0 problem(s)`. The container is the pinned
production image on `/health` 200.

## What this decides

Production stays. The dev composition is not a replacement on this evidence: it is 8 percent slower at decode,
11 to 18 percent slower at cold prefill above 8k, and slower on the warm agent turn. The campaign's target is now
the attribution of that 8 percent, starting from the parity diff this window makes possible: P carries our
0001-0028 plus the zmerge8 keep set and two kindling boot fixes on an older release, D carries upstream main plus
the 40-patch composition, and the two environments overlap on 22 names with the rest classified in
`docs/receipts/ProdEnvAudit/` and `scripts/qwen38/zig/target/env/register.env`.

## Files

`ev.tgz` (405 entries) is the per-cell evidence for every boot: env, cmd, image id, boot log, decode JSONL with
per-request hashes, TTFT output, golden record, thermals. `tables.md` is the summariser's full output, `score1.txt`
and `score2.txt` the two spread passes, `run.log` the execution log with every CELL-DONE and the RESTORED line,
`in/` the harness and input copies the driver used, `restored/` the restore proof. The per-cell tree itself
remains on spark6 at `~/work/parity/out` and is not tracked.

Not taken in this window: under-load TTFT at each level, the target's 120k TTFT cases and its 1k thinking-on cell,
RigMark, and the target's 256-token cells. D's sequence-memory column is empty in the boot table, so its admitted
memory at each level is not recorded here.
