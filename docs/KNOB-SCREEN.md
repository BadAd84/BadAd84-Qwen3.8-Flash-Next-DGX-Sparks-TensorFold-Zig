# The knob screen: the rule, the twelve arms, their verdicts

Current state of the screen lane. The rule and the window machinery live in `work/KnobScreen/`
(`RULE.md`, `driver.sh`, `analyze.py`); the raw boot records, the clients' own outputs and `scores.tsv`
live under `work/KnobScreen/out/` when the window has run. This page is the durable record: what was
screened, by what rule, what each arm returned, and what stage two inherits.

Status at 2026-11-23T12:02Z: the window is queued on spark6's GPU lock behind Int4Device (holder at that
time) and EnvBoot (second in the queue), gated on EnvBoot's fast r5 prompt-following marker; no arm has
booted. This line is replaced by the verdicts below when the window runs. A screen is never a verdict: a
PROMOTE only earns the five-level A/B later, and **nothing here is written into `dev.env`**.
Status as of the last box reading, 2026-11-23T12:29:36Z: **armed and queued, not run.** The box rebooted at 12:15:31Z and killed all
three windows (EnvBoot's, Int4Device's, this lane's). The queue re-formed as EnvBoot's fast half,
Int4Device's contract window, this window, then EnvBoot's long half, and Main added a second gate: this
window starts only when `~/work/EnvBoot/FAST-VERDICT` has `CLEAN` on its first line **and**
`~/work/KnobScreen/GO` exists (Main writes GO after the int4 device receipt lands). A detached starter,
`/home/adam/work/KnobScreen/starter.sh`, waits for both **without holding the lock**, and starts the C-A-C
window under `flock` the moment both are present; a `DEFECT` line writes `out/GATE-STOP` and exits without
touching production or the lock. At the last reading the lock was held by Int4Device's requeued build and
neither gate existed, so **no arm has booted and there are no verdicts**. EnvBoot has separately reported
r5 prompt following clean on the complete 1,664-body rows (echo 1/500 on both arms, GSM8K 96.8 percent,
r5 FP4 byte-identical to the 2026-11-19 build), which is the evidence its marker will carry.

## Why a screen

`docs/KNOB-COVERAGE.md` classifies all 78 settings the served tree reads and lists 20 UNMEASURED ones
whose read site can move decode or prompt speed. The repo's five-level interleaved ABBA gives one
setting a real verdict, but it costs five boots a level and is too slow to spend on twenty settings that
will mostly be level.

So the 20 are screened first: three boots a candidate (control, candidate, control), one arm a boot, and
a rule decided in advance that sorts each candidate into PROMOTE, KILL or INCONCLUSIVE. The window is
capped at 12 candidates or 8 hours. The remaining eight stay on the worklist, untouched and unjudged.

## The rule, in one page

The full rule is `work/KnobScreen/RULE.md`, written before the first row. In short:

- **Subject.** The r5 FP4 dev image, pinned by id
  (`tensorfold-qwen38:qr-a-r5-1ece6e6db`, `sha256:001fc6ff...`), booted through the recipe launcher with a
  copy of the committed `dev.env`. A candidate's copy differs in **exactly one line**, asserted by the
  writer before it boots. Nothing is built.
- **Boot arguments.** Production's shape, identical on every boot: 8 lanes, 262,144 tokens, fp8 KV,
  vision off, drafts on, `TENSORFOLD_CUDA_KERNELS=native` as a launcher pin, loopback only.
- **Boots.** Three a candidate, in the order control, candidate, control. The second control is the null
  arm: its disagreement with the first is the spread every verdict is measured against.
- **Cells.** Decode at 1 and 4 streams on the prose and code prompts at temperature 0 (greedy, 256
  tokens, 3 reps, `aggregate_tps`); one sampled 4-stream cell at temperature 1.0 (the only cell that
  reaches `SAMPLED_HEADS`); cold TTFT at 2k and 32k (thinking off, idle, 3 reps).
- **Spread and margin.** Per cell, `s = |c1 - c2| / ((c1 + c2)/2)`, measured in the same window; every
  test uses the margin `m = max(s, 0.01)`. The 1 percent floor is the resolvability floor, added before
  any row after checking the rule against `work/ProseDraft/RESULT.md`'s own numbers: at that receipt's 0.1
  percent repeat spread a rule with no floor kills an arm it records as level at minus 0.24 percent.
- **Verdicts, in precedence.** FINDING (digest, prompt tokens, boot, health, foreign traffic, or greedy
  text changed) - no verdict. UNSTABLE (any raw spread above 25 percent) - INCONCLUSIVE. KILL (worse than
  both controls beyond the margin in any judged cell). PROMOTE (better than both beyond the margin in
  every treatment cell, no guard cell worse). Otherwise INCONCLUSIVE.
- **INCONCLUSIVE is reported, never retried into PROMOTE.** A large control spread is itself the result:
  that cell cannot resolve a change of that size on this box today.

## The twelve arms

The order is `docs/KNOB-COVERAGE.md`'s rank, truncated at the 12-candidate cap: the eight A1 per-round
leads, then the first four A2 prompt-pass leads.

| # | setting | arm | class | why it is here |
| --- | --- | --- | --- | --- |
| 1 | `TF_FLASHNEXT_ATTN_LANES` | 0 to 1 | A1 | a shared round's attention in one launch a kernel; the 1.2.6 stack measured 0 to 2 percent alone and 3.1 stacked, and this stack has it off |
| 2 | `TF_FLASHNEXT_DECODE_GRAPH` | 0 to 1 | A1 | one bounded decode round as a CUDA graph; legal at TP=1 because the dense-split refusal needs `applies()`, false at world != 2 |
| 3 | `TF_FLASHNEXT_WINDOW_GRAPH` | 1 to 0 | A1 | drafted windows and head pieces eager instead of replayed graphs; capture cost against replay saving is unmeasured |
| 4 | `TF_QMMF_HALF_BELOW` | 96 to 0 | A1 | no 32-column half tiles for short calls, same sums; 128 is the other extreme and leaves decode unchanged, so 0 is the informative arm |
| 5 | `TF_FLASHNEXT_BATCH_DRAWS` | 1 to 0 | A1 | per-stream row draws instead of batched; a launcher value never A/B'd on this stack |
| 6 | `TF_FLASHNEXT_SHARED_SIDE` | 1 to 0 | A1 | shared expert inline after the routed experts instead of on its own stream |
| 7 | `TF_FLASHNEXT_SAMPLED_HEADS` | 1 to 0 | A1 | sampled streams drafted separately; judged on the sampled cell, which is why the window carries one |
| 8 | `TF_FLASHNEXT_KEEP_LATE` | unset to 1 | A1 | pending DeltaNet rows kept in a log instead of re-run; one GPU only |
| 9 | `TF_FLASHNEXT_PROMPT_BF16` | 1 to 0 | A2 | the other prompt path instead of BF16 prompt tiles |
| 10 | `TF_FLASHNEXT_READOUT_ROWS` | 64 to 128 | A2 | read-out fused tiles from 128 rows instead of 64 |
| 11 | `TF_FLASHNEXT_FACT_ROWS` | 64 to 128 | A2 | NVFP4 prompt tiles from 128 rows instead of 64 |
| 12 | `TF_FLASHNEXT_WARM_AHEAD` | 0 to 1 | A2 | PLE warm-ahead hints on |

What the cap left out, in rank order: `TF_FLASHNEXT_TABLE_WARM`, `TENSORFOLD_CUDA_KERNELS` (A3);
`TENSORFOLD_PREFIX_WAIT_MS`, `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS`, `TF_PROMPT_INTERMEDIATE`,
`TENSORFOLD_RESTORE_PREFETCH`, `TENSORFOLD_RESTORE_PREFETCH_GIB`, `TENSORFOLD_RESTORE_PREFETCH_MS` (A4).
They are stage two's worklist; none of them was measured or touched. The A4 group is cache and resume
tuning and cannot be judged by this window's cells at all (they need a resume or two interleaved
conversations), which is why the cap costs least there.

## The instrument

- `work/KnobScreen/driver.sh` takes the GPU lock with `flock` and refuses to screen until EnvBoot's r5
  prompt-following verdict is on disk as `CLEAN` (the gate). It stops production only after the lock,
  runs a **preflight boot with cells** before any arm, then the C-A-C boots, then restores production and
  checks `/health` 200 against the pinned production image id (`PROD-IMAGE-OK`). Budget starts at lock
  acquisition, not at queue time.
- **The launcher is the recipe's `start.sh`, not `$HOME/qwen6-start.sh`.** The dev serve's launcher
  `exec env`s a 56-name block of its own. Measured against `dev.env`: 7 of the 56 are also in dev.env and
  all 7 carry the same value on both sides, so it would replace none of this file's settings. It is not the
  base because of the other 49: it injects levers dev.env does not carry, including `TF_FLASHNEXT_HC_Q12=1`,
  which dev.env records as a measured negative and deliberately omits. A screen of dev.env's settings runs
  on dev.env alone; the recipe passes every `TENSORFOLD_*`/`TF_FLASHNEXT_*` name that is set in its
  environment and nothing else, so the arm file is the environment. (Correction of record: my first version
  of this line claimed the launcher replaced CHUNK, CHUNK_SOLO, KV_PAGES, SHARED_DRAFTS, READOUT_FUSED,
  PROMPT_SHARED_DIRECT and WINDOW_CHECK. It does not; EnvBoot measured the 7-name overlap and I recomputed
  it from `box-snapshot/qwen6-start.sh` against `ref/dev.env`.)
- **Every boot proves the arm reached the container.** `check_env.py` compares the container's own
  environment with the arm file: a missing name, a different value, or a presence-test name that is set,
  refuses the boot before its cells run and retries once on a fresh boot. That is what stops a screen from
  scoring a control twice.
- **The rule was checked against the repo's own verdicts before the first row.** `work/KnobScreen/sens.py`
  feeds the rule the shared-drafts receipt's measured 4-stream numbers (`work/ProseDraft/RESULT.md:68-84`)
  in the writers' shape. With the 1 percent resolvability floor, the one arm the repo promoted (S0, plus
  10.2 percent) comes out PROMOTE and the arms it recorded level (G8 at minus 0.2 percent, C20 at plus
  0.1 percent) come out INCONCLUSIVE. Without the floor, G8 was killed at minus 0.24 percent against a 0.1
  percent control spread, which is why the floor exists in the rule.
- **The dry run precedes the window.** `driver.sh dry` writes stub boots in the exact shape the clients
  write (`conc.json` cells with `alone`/`serial`/`reps[].requests[].prompt_tokens`; `ttft.py`'s summary
  lines), scores them with the real analyzer, and must print PROMOTE, KILL and INCONCLUSIVE (and an
  UNSTABLE control case) before any GPU time is spent. It is green.

## The window

See `work/KnobScreen/RESULT.md` for the per-candidate table, the spreads and the end state, and
`work/KnobScreen/out/scores.tsv` for the machine-readable rows.
