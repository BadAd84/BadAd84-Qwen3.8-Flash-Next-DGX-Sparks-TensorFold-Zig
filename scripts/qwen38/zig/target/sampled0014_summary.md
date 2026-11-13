# PR 3218 (TF_FLASHNEXT_MTP_WEIGHTS): sampled decode, and the drafter on against "draft": false

The checklist line: "Decode and prompt processing are no slower than main at one stream and the widest admitted; with
`--drafter`, no slower than without it, greedy and sampled." Measured on spark6, 2026-11-13: upstream main 6c5cef8
(image `um`, d536ecc4f646) against main + the PR (image `um14`, 81d89a568016) with the setting unset and with
`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`. NVFP4 checkpoint, bf16 KV, 131,072 window, `--parallel 4` (the widest admitted is
4), MEM_CHECK=0, the rpr recipe's environment, a fresh boot an arm, GPU lock held by `flock -o`, production restored
after each run (/health 200 at 18:47:21 and 19:36:49 UTC). Clients: upstream `tools/` at the PR's base 6c5cef8
(`bench_concurrent.py` c663d05c, `bench_openai.py` edf63629).

This family's drafter is the checkpoint's MTP head; the serve has no `--drafter` flag to drop, so "without it" is
upstream's request field `"draft": false` (what `bench_concurrent.py --serial` sends). `bench_nodraft.py` runs
`bench_concurrent.py` unchanged with that field on every request.

Run 1, `sampled0014.sh`, boots main, PR unset, PR mxfp8, main again, each in this order (URL MODEL as served):

    python3 up-tools/bench_openai.py URL MODEL --tokens 256 --reps 3 --temperatures 1.0
    python3 up-tools/bench_concurrent.py URL MODEL --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 1.0
    python3 bench_nodraft.py URL MODEL --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 1.0
    python3 bench_nodraft.py URL MODEL --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 0
    python3 up-tools/bench_concurrent.py URL MODEL --tokens 256 --reps 3 --levels 1,2,4 --alone --serial --temperatures 0
    python3 exact/served_exactness.py drafts URL MODEL exact/prompts.json drafts.json --tokens 64

Run 2, `sampled0014b.sh`: six more boots, main, unset, mxfp8, mxfp8, unset, main, after one throwaway warm-up pass;
each boot `bench_openai.py --reps 9` (seeds 1234-1242) and the sampled `bench_concurrent.py` line above.
Tables: `sampled0014_sum.py sampled0014 OUT` (run 1, full tables in `sampled0014/summary.md`) and
`sampled0014_pool.py OUT sampled0014 sampled0014b` (all boots, `sampled0014b/pool.md`). Raw JSON and run logs:
`sampled0014/`, `sampled0014b/`. Aggregate tok/s is bench_concurrent's median of 3 reps; "main spread" is
|main - main again| over their mean; a PR cell is flagged when it is below both main boots.

## Run 1: drafter on, against main

| temperature | prompt | streams | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|---|---|
| 1 | code | 1 | 69.9 | 68.8 | 71.2 | 68.7 | 1.7% | -0.7% | +2.7% |
| 1 | code | 2 | 87.8 | 86.2 | 88.0 | 86.3 | 1.7% | -1.0% below both | +1.1% |
| 1 | code | 4 | 127.0 | 125.1 | 127.9 | 124.8 | 1.7% | -0.6% | +1.6% |
| 1 | chat | 1 | 44.4 | 43.7 | 43.5 | 44.1 | 0.7% | -1.2% below both | -1.7% below both |
| 1 | chat | 2 | 69.1 | 68.2 | 68.0 | 68.9 | 0.3% | -1.2% below both | -1.4% below both |
| 1 | chat | 4 | 102.6 | 101.7 | 102.3 | 102.3 | 0.3% | -0.7% below both | -0.1% |
| 0 | code | 1 | 71.3 | 72.2 | 73.7 | 71.4 | 0.1% | +1.2% | +3.3% |
| 0 | code | 2 | 135.3 | 137.0 | 141.5 | 135.8 | 0.4% | +1.1% | +4.4% |
| 0 | code | 4 | 236.6 | 240.1 | 246.8 | 237.2 | 0.3% | +1.4% | +4.2% |
| 0 | chat | 1 | 45.8 | 46.5 | 46.3 | 45.8 | 0.0% | +1.5% | +1.1% |
| 0 | chat | 2 | 84.8 | 85.8 | 87.9 | 85.2 | 0.5% | +0.9% | +3.4% |
| 0 | chat | 4 | 152.6 | 154.2 | 156.1 | 152.6 | 0.0% | +1.0% | +2.3% |

One stream at temperature 1.0, `bench_openai.py` decode_tps, median of seeds 1234-1236:

| prompt | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|
| fibonacci-raw | 65.8 | 64.7 | 67.9 | 64.2 | 2.5% | -0.5% | +4.5% |
| gpu-chat-no-think | 45.8 | 44.8 | 47.6 | 44.6 | 2.5% | -0.9% | +5.3% |

## Run 1: "draft": false, against main

| temperature | prompt | streams | main | PR, unset | PR, mxfp8 | main again | main spread | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|---|---|
| 1 | code | 1 | 26.8 | 26.8 | 26.7 | 26.7 | 0.4% | +0.2% | -0.2% |
| 1 | code | 2 | 45.6 | 45.5 | 45.5 | 45.5 | 0.2% | -0.1% | -0.1% |
| 1 | code | 4 | 72.2 | 72.2 | 72.1 | 71.8 | 0.6% | +0.3% | +0.1% |
| 1 | chat | 1 | 26.9 | 26.7 | 26.8 | 26.8 | 0.4% | -0.6% below both | -0.2% |
| 1 | chat | 2 | 45.4 | 45.2 | 45.3 | 45.2 | 0.4% | -0.2% | +0.0% |
| 1 | chat | 4 | 70.9 | 71.2 | 70.9 | 71.2 | 0.4% | +0.2% | -0.2% |
| 0 | code | 1 | 27.0 | 26.9 | 26.9 | 27.0 | 0.0% | -0.4% below both | -0.4% below both |
| 0 | code | 2 | 50.8 | 50.7 | 50.7 | 51.0 | 0.4% | -0.4% below both | -0.4% below both |
| 0 | code | 4 | 90.6 | 91.0 | 90.9 | 91.9 | 1.4% | -0.3% | -0.4% |
| 0 | chat | 1 | 26.6 | 26.8 | 26.9 | 26.7 | 0.4% | +0.6% | +0.9% |
| 0 | chat | 2 | 50.3 | 50.7 | 50.8 | 50.3 | 0.0% | +0.8% | +1.0% |
| 0 | chat | 4 | 91.0 | 91.3 | 91.6 | 90.7 | 0.3% | +0.5% | +0.8% |

## Run 1: drafter on against "draft": false, same boot (on / off aggregate tok/s)

| temperature | prompt | streams | main | PR, unset | PR, mxfp8 | main again |
|---|---|---|---|---|---|---|
| 1 | code | 1 | 2.61x | 2.57x | 2.67x | 2.57x |
| 1 | code | 2 | 1.93x | 1.89x | 1.93x | 1.90x |
| 1 | code | 4 | 1.76x | 1.73x | 1.77x | 1.74x |
| 1 | chat | 1 | 1.65x | 1.64x | 1.62x | 1.65x |
| 1 | chat | 2 | 1.52x | 1.51x | 1.50x | 1.52x |
| 1 | chat | 4 | 1.45x | 1.43x | 1.44x | 1.44x |
| 0 | code | 1 | 2.64x | 2.68x | 2.74x | 2.64x |
| 0 | code | 2 | 2.66x | 2.70x | 2.79x | 2.66x |
| 0 | code | 4 | 2.61x | 2.64x | 2.72x | 2.58x |
| 0 | chat | 1 | 1.72x | 1.74x | 1.72x | 1.72x |
| 0 | chat | 2 | 1.69x | 1.69x | 1.73x | 1.69x |
| 0 | chat | 4 | 1.68x | 1.69x | 1.70x | 1.68x |

Checks, every arm: concurrent == alone 42/42 in each of the four runs, alone == serial 8/8 (1.0) and 2/2 (0), 0 failed
and 0 unmeasured requests; tokens a chunk 2.31-5.22 drafter on and 1.00 in every "draft": false cell; served_exactness
drafts 8/8 equal, 0 drafted tokens in every "draft": false reply, 5-54 accepted in the drafted ones.

## All ten boots, sampled decode with the drafter on

Main: run 1's main and main again, run 2's main-1 and main-2; PR unset: pr-default, pr-default-1, pr-default-2; PR
mxfp8: pr-mxfp8, pr-mxfp8-1, pr-mxfp8-2 (boots listed in that order).

| prompt | streams | main: mean (boots) | PR, unset: mean (boots) | PR, mxfp8: mean (boots) | main range | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|---|---|
| code | 1 | 69.2 (69.9, 68.7, 68.6, 69.7) | 69.0 (68.8, 68.7, 69.5) | 70.6 (71.2, 70.1, 70.4) | 1.9% | -0.3% | +1.9% |
| code | 2 | 86.9 (87.8, 86.3, 86.3, 87.3) | 86.6 (86.2, 86.4, 87.2) | 87.2 (88.0, 86.8, 86.9) | 1.7% | -0.4% | +0.4% |
| code | 4 | 125.7 (127.0, 124.8, 124.9, 126.2) | 125.3 (125.1, 124.8, 125.9) | 126.9 (127.9, 126.3, 126.5) | 1.7% | -0.4% | +0.9% |
| chat | 1 | 44.0 (44.4, 44.1, 43.5, 44.2) | 43.8 (43.7, 43.7, 44.1) | 43.2 (43.5, 42.7, 43.3) | 2.0% | -0.5% | -2.0% below every main boot |
| chat | 2 | 68.5 (69.1, 68.9, 68.0, 68.2) | 68.4 (68.2, 68.1, 68.8) | 67.7 (68.0, 67.2, 68.0) | 1.6% | -0.3% | -1.2% below every main boot |
| chat | 4 | 101.7 (102.6, 102.3, 100.8, 101.0) | 101.6 (101.7, 101.1, 102.0) | 101.8 (102.3, 101.1, 102.1) | 1.8% | -0.1% | +0.2% |

One stream at temperature 1.0, `bench_openai.py` decode tok/s, each arm's mean over its boots per seed, then the mean
over seeds (per-seed rows in `sampled0014b/pool.md`):

| prompt | main | PR, unset | PR, mxfp8 | PR, unset vs main | PR, mxfp8 vs main |
|---|---|---|---|---|---|
| fibonacci-raw, mean of seeds 1234-1242 | 62.5 | 63.0 | 63.9 | +0.7% (5/9 seeds faster) | +2.2% (8/9 seeds faster) |
| gpu-chat-no-think, mean of seeds 1234-1242 | 44.8 | 45.4 | 45.7 | +1.2% (5/9 seeds faster) | +1.9% (7/9 seeds faster) |
| gpu-chat-no-think, seed 1234 only | 43.9 | 43.8 | 43.0 | -0.2% | -2.1% |

## Verdict

Against main. With one boot an arm (run 1), 11 PR cells sit below both main boots: six sampled drafter-on cells (unset:
code at 2 streams -1.0%, chat at 1, 2 and 4 streams -1.2%, -1.2%, -0.7%; mxfp8: chat at 1 and 2 streams -1.7%,
-1.4%) and five "draft": false cells by 0.1-0.2 tok/s (0.4-0.6%). The unset arm returns main's tokens (exact0014) with
main's tokens a chunk in every cell, and in the same run it was above both mains in every greedy cell (+0.9% to +1.5%). With
ten boots of the sampled cells, the unset arm is inside main's boot range in all six (-0.1% to -0.5% on the mean;
main's own range 1.6-2.0%). mxfp8 is still below every main boot in two cells: chat at 1 stream (43.2 against
43.5-44.4, -2.0%) and at 2 streams (67.7 against 68.0-69.1, -1.2%). Those cells use seeds 1234 and 1234-1235, where
the re-coded drafter's sampled drafts are accepted less often (run 1 tokens a chunk 2.31 against 2.39 at 1 stream,
2.38 against 2.45 at 2); over nine seeds at one stream mxfp8 is +2.2% (code) and +1.9% (chat), slower than main on 1
of 9 code seeds and 2 of 9 chat seeds, chat seed 1234 the worst at -2.1%. mxfp8's other sampled cells are +0.2% to
+1.9% and its greedy cells +1.1% to +4.4%. So with the setting unset no cell is slower than main outside main's
spread, greedy or sampled, at 1 or 4 streams. With mxfp8, sampled chat at 1 stream is slower than main (seed 1234,
-2.0%, below every main boot), while at 4 streams, the widest admitted, no cell is slower. The five "draft": false
cells were not re-run with more boots. Prompt processing was not part of these runs (cold prompts: receipt0014).

With the drafter against without it. Drafter on is faster than "draft": false in all 48 cells (4 arms, greedy and
sampled, code and chat, 1/2/4 streams): 1.43x-2.79x, the smallest sampled chat at 4 streams (1.43x-1.45x). The
"draft": false requests really ran without drafts: tokens a chunk 1.00 in every off cell, and the server reported 0
drafted tokens for every "draft": false reply. This half of the line holds in every arm, greedy and sampled.
