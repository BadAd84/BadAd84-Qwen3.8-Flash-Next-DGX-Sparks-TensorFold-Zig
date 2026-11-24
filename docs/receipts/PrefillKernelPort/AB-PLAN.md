# 0041 A/B plan: the 64-column fused prompt tile

The window this plan is for has NOT been queued (spark6's GPU is saturated; a confirm window runs and two sessions'
windows are queued behind it). This file is the plan an operator runs when a window frees, in the shape
`docs/receipts/ParityGap/PLAN.md` section 6 uses (one fresh boot a cell, the driver takes `~/work/gpu.lock` and
restores production in its EXIT trap).

## Arms

All three arms are the dev engine of this composition (`patches/main-1ece6e6db-r5-dev`, 41 patches), the same image,
the same checkpoint, the same served env (`dev.env`), differing by the KS names alone:

| arm | lever | boot-line proof |
|---|---|---|
| F0 | `TF_FLASHNEXT_PROMPT_KS_N=0` (control; the engine's 128-column prompt tile) | no `prompt matmuls:` line |
| F1 | `TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=8` (the captured geometry) | `prompt matmuls: the fused K-slice tile on 64-column blocks, 8 row tiles a band (TF_FLASHNEXT_PROMPT_KS_N)` |
| F2 | `TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=0` (the 64-column block, the engine's own sweep) | the same line with `0 row tiles a band` |

F2 separates the two changes: F2 vs F0 is the column block alone; F1 vs F2 is the band alone.

## Cells

One fresh boot a cell, with F0 and F1 bracketing F2 in the C=1 and C=8 screens:

- **cold TTFT** at 8k and 32k (prompt kinds: thinking off and on), C=1 and C=8. This is the lever's target: the
  whole effect is prefill, measured by the harness's own `ttft.out` prefill component (`summary ... prefill`).
- **decode** at C=1, 2, 4, 6 and 8 (3 passes, 512 greedy tokens, prose then code). The lever changes no decode
  kernel, so decode must be inside the control's boot spread; a decode difference means the arm is not an isolation.
- **warm 100k + 2k agent turn** (2 reps, cached tokens recorded) as the workload-level check.
- **golden 6/6** against the recorded stock reference at every cell, plus a per-cell reply hash compare.

The harness is this directory's `driver/window.sh`, derived from `docs/receipts/ParityGap/driver/window2.sh` (the
window the A2 expectation was measured with) with the three arms and the single-family level list; its arms file is
`driver/boot_env.sh`, its scorer `driver/score_pks.py` (the same per-cell decode/TTFT extraction, reading the control
F0), and its hasher `driver/hash_cmp.py` and round counter `driver/rounds.py` are the ParityGap instruments unchanged.

At C=8 the 64-column tile's blocks are 2x the 128-column tile's (`cdiv(m,128)*cdiv(n,64)` against
`cdiv(m,128)*cdiv(n,128)`), so a level where the tile's blocks no longer fill half the SMs is where F1 could lose:
record the SM count and the block count per cell.

## What the numbers confirm or refute

The expectation, from `docs/receipts/ParityGap/RESULTS.md` ("A2") and its own harness split: production's one-program
prompt matmul is worth `1.121` at cold 8k and `1.136` at cold 32k against its own two-launch fallback, byte-identical
replies and no decode change; in wall time at C=1 the prefill component is `2.613 s` (one-program) against
`2.930 s` (two-launch) at 8k and `10.459 s` against `11.889 s` at 32k, i.e. **`+0.31 s` per 8k prompt and `+1.31 s`
per 32k prompt**.

- **Confirmed** when F1's prefill component is BELOW F0's by at least the arm's own boot-to-boot spread at both 8k and
  32k, with the replies byte-identical and decode inside the spread. The candidate then lands as a default-on dev
  lever (a separate promotion step, `PROMOTION-RULES.md`).
- **Refuted** when F1 is at or above F0 at both prompt sizes (the 64-column block buys nothing on this engine; the
  captured kernel's advantage is its staging, not its column block), or when F1's replies differ from F0's (the lever
  is not output-neutral and must not ship on this evidence).
- **Partial** when only one prompt size moves, or the band and the column block pull opposite ways (F1 vs F2). Record
  which half moved; a half that moves alone is the lever to keep.

## Exact commands

From the workstation (`export SSH_AUTH_SOCK=C:/Users/Adam/AppData/Local/gnupg/agent-gui/S.gpg-agent.ssh.cyg`):

```
ssh adam@192.168.99.16 'mkdir -p ~/work/pks/out'
scp docs/receipts/PrefillKernelPort/driver/boot_env.sh docs/receipts/PrefillKernelPort/driver/window.sh \
    docs/receipts/PrefillKernelPort/driver/score_pks.py \
    adam@192.168.99.16:work/pks/
ssh adam@192.168.99.16 'cd ~/work/pks && setsid nohup env LOG=$HOME/work/pks/out/run.log \
    bash window.sh >> window.log 2>&1 < /dev/null & echo LAUNCHED $!'
ssh adam@192.168.99.16 'tail -5 ~/work/pks/out/run.log; grep -c "^\[.*CELL-DONE" ~/work/pks/out/run.log'
```

The driver takes `flock -o -w 43200 ~/work/gpu.lock` itself, boots each cell from `boot_env.sh`, stores the container's
own env and argv at every boot (so the lever is proved from the boot, not asserted), empties the KV tier's store from a
throwaway container before every boot, and restores production (`/health` 200, the pinned image id,
`check-prod-env.py --inspect` at 0 problems) in its EXIT trap. It writes `WINDOW-DONE` as its last line.



Deliverables on disk: `~/work/pks/out/` (per-cell env, argv, boot log, decode JSONL with token hashes, TTFT output,
golden record, thermals), `score.md` (the per-arm table), `restored/` (the restore proof). These land as
`docs/receipts/PrefillKernelPort/RESULTS.md` when the window completes.
