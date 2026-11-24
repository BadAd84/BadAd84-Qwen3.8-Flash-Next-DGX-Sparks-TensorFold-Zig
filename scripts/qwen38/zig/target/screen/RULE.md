# The screen's decision rule

This directory is the screen's kit: `driver.sh` takes the lock and runs the window, `analyze.py` scores it
by the rule below, `basefilter.py` materialises the base the launcher can carry, `check_env.py` proves each
boot's environment, `mkenv.py` writes an arm, `stub_cells.py` writes the dry run's cells, `result.py`
composes `out/RESULT.md`. Rows are in `out/`, the verdicts in `out/scores.tsv` and `out/RESULT.md`.

## What a screen is

The served tree's table carries 95 settings in scope; `dev.env` states them all, unmeasured alternatives
included. A five-level interleaved ABBA per setting is too slow to spend on settings that will mostly be
level, so this window is a **screen**: it sorts candidates into PROMOTE, KILL, KILL-PENDING and
INCONCLUSIVE. **A screen is never a verdict.** A PROMOTE earns the full five-level A/B later; it promotes
nothing on its own, and nothing is written into `dev.env` by this lane.

## The subject: one setting changed, nothing else

- The image is the r5 FP4 dev serve, pinned by id: `tensorfold-qwen38:qr-a-r5-1ece6e6db`,
  `sha256:001fc6ff...b00063`. No build in this window: env only.
- **The base is the committed `scripts/qwen38/zig/target/env/dev.env`, copied at start with its sha256
  recorded** (`out/ref.txt`). The driver refuses a copy whose sha differs from the pin install wrote, so a
  stale `ref/` cannot become the base of a window.
- **The launcher's filter decides what is on the base.** The recipe launcher builds its `-e` arguments from
  `env | grep -E '^(TENSORFOLD|TF_)[A-Z0-9_]+='` (start.sh, as deployed; the copy on spark6 reads that line).
  `basefilter.py` keeps every line whose NAME matches that class (its default pattern omits the trailing `=`,
  since it matches names), comments the lines it cannot (`# NOT-CARRIED export ...`) and lists them in
  `out/base-not-carried.txt`. Those settings are absent from the container on every boot of this window, so
  no arm sets one and no verdict reads one; the receipt names the list and the count.
- **A setting the launcher cannot carry is never an arm.** `plan_gate` refuses such a plan row
  (`PASSAGE-REFUSED`) before any boot, and `mkenv.py` refuses it again at the point of writing the arm.
  The same gate refuses a row whose value equals the base's own value (`PLAN-NO-OP`): that arm would
  silently measure the control twice.
- **The boot goes through the recipe launcher `~/work/lanes/rpr/recipe/start.sh`, not `$HOME/qwen6-start.sh`.**
  That script `exec env`s a 56-name block of its own, including `TF_FLASHNEXT_HC_Q12=1`, which `dev.env`
  records as a measured negative and deliberately omits. A screen of `dev.env`'s settings runs on the
  carried `dev.env` alone. The receipt records the launcher's and its `config.sh`'s shas.
- Boot arguments, identical for every boot: `PREPARE=0 IMAGE=<the pinned tag> CHECKPOINT=nvfp4 VISION=0
  TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=8 CONTEXT=262144 HOST=127.0.0.1 PORT=8888
  MEM_CHECK=0 THINKING=0 DRAFTS=1`. `TENSORFOLD_CUDA_KERNELS=native` is required: both images bake a
  captured kernel set, which refuses `--kv-cache fp8` and paged KV, and this env sets both.
- An arm is a copy of the base with exactly one line changed. The writer asserts the old line occurs
  exactly once, quotes it above the new line, and re-reads the file to verify the single new line.

## Boots per candidate: warm-up, control, candidate, control, and a confirm when needed

1. **One discarded warm-up boot** before the first arm: the base env, the same boot arguments, its own cells
   written under `out/warmup/w/`. It proves the serve shape and takes the first-boot penalty. The analyzer
   reads only plan arms, so no verdict reads its cells, and the receipt states how many pairs it had to
   pool.
2. **C-A-C**: control, candidate, control, one arm a boot, each a fresh boot. `c1` and `c2` are the
   controls; a cell's value is `mid = (c1 + c2)/2`.
3. **a2, only on a single-cell KILL shape**: when one candidate boot loses exactly one treatment cell
   beyond the margin and no second judged cell is lost, the verdict is `KILL-PENDING` and the driver boots
   the candidate once more (`a2`) in the same arm. The second boot either confirms the loss (KILL) or leaves
   it inside run-to-run variation (INCONCLUSIVE). A `KILL-PENDING` with no budget left for the confirm boot
   stays pending in the receipt; it is never reported as a KILL.

Every boot is preceded by one discarded prime request, so no cell is the first traffic after a fresh boot.

## The cells

Measured on every boot, in this order, by the tools' own outputs:

| cell | tool | how | value |
|---|---|---|---|
| `d1-prose` | `bench_concurrent.py` | chat prompt, 1 stream, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d1-code` | `bench_concurrent.py` | code prompt, 1 stream, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d4-prose` | `bench_concurrent.py` | chat prompt, 4 streams, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d4-code` | `bench_concurrent.py` | code prompt, 4 streams, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d4-sampled` | `bench_concurrent.py` | chat prompt, 4 streams, temperature 1.0, seeded, 256 tokens, 3 reps | median `aggregate_tps` |
| `c2k` | `ttft.py` | cold 2,048-token prompt, thinking off, idle, 3 reps, 16 max tokens | median TTFT (`cold2k-off`, idle) |
| `c32k` | `ttft.py` | cold 32,768-token prompt, thinking off, idle, 3 reps, 16 max tokens | median TTFT (`cold32k-off`, idle) |

The exact command lines, the seed (`--seed 1234`), the temperatures (`--temperatures 0,1.0`), the token
counts, the reps and the sizes are the spec string the digest is taken over. `--alone --serial` are on.

`d4-sampled` is **report-only for every candidate except `TF_FLASHNEXT_SAMPLED_HEADS`**: it appears in the
table and `scores.tsv`, its spread is computed, and it enters no verdict for the others (its read site only
runs at temperature above zero). For `SAMPLED_HEADS` it is that candidate's treatment cell. The
text-change finding applies to the greedy cells only: at temperature 1.0 a reply is a seeded draw, so
`d4-sampled`'s `alone`/`serial` comparisons are recorded and printed, never a finding.

Directions: **higher is better** for the five `d` cells; **lower is better** for the two `c` cells.

## The digest, and what makes a boot a FINDING

A boot's `digest` is `sha256(sha256(bench_concurrent.py) + sha256(ttft.py) + spec)`. It is recorded in the
boot's `meta.json`. A boot is a **FINDING, not a result**, when any of these hold:

1. its digest differs from the control boot's digest;
2. any cell's `prompt_tokens` differs from the control's for the same cell;
3. `boot_rc` is not 0, or `/health` is not 200, or `/v1/models` names no model, after one fresh retry;
4. a measured cell reports `failed` or `unmeasured` above zero;
5. the server log carries a request from a client that is not `127.0.0.1`;
6. a `d` cell's `alone` or `serial` comparison returns `unequal` above zero: the greedy text changed.

A candidate with a FINDING on any of its boots gets **no verdict**: it is reported
`INCONCLUSIVE-FINDING` with the finding named. A finding is never retried into a verdict.

## The spread, pooled over the window's own control pairs

For each cell `i`, every arm contributes its control pair: `s_pair = |c1_i - c2_i| / mid_i`. The cell's
**pooled spread** `s_i` is the median of those per-arm pair spreads, and every test uses the margin
`m_i = max(s_i, 0.01)`. The 1 percent floor is the resolvability floor: on the shared-drafts receipt a
0.1 percent repeat spread would kill an arm the repo records level at minus 0.24 percent.

Pooling is why eleven arms and not one pair decide the margin: one noisy pair cannot widen every verdict and
one lucky pair cannot narrow them. Two guards remain per arm: a pair spread `> 0.25` makes **only its own
arm** INCONCLUSIVE, and a pooled spread `> 0.25` makes the whole window unable to resolve that cell
(every arm reports INCONCLUSIVE).

```
mid_i   = (c1_i + c2_i) / 2
s_pair  = |c1_i - c2_i| / mid_i                 this arm's own control-to-control spread
s_i     = median(s_pair over all arms)          the pooled spread, the window's estimate
m_i     = max(s_i, 0.01)                        the margin every test uses
delta_i = (a_i - mid_i) / mid_i                 positive = more throughput; for c cells negative = faster
```

## The verdict, and its asymmetry

- **better than both, beyond the margin**: `a_i > c1_i*(1+m_i)` and `a_i > c2_i*(1+m_i)` for a `d` cell;
  `a_i < c1_i*(1-m_i)` and `a_i < c2_i*(1-m_i)` for a `c` cell.
- **worse than both, beyond the margin**: the reverse on both controls.

Verdicts, in this precedence:

1. **FINDING** -> `INCONCLUSIVE-FINDING`.
2. **UNSTABLE** -> `INCONCLUSIVE`: this arm's own pair spread above 25 percent in any judged cell, or a
   pooled spread above 25 percent in one.
3. **KILL**: a **treatment cell** worse than both controls beyond the margin, and corroboration, meaning
   either a second judged cell also lost in the same boot, or the same treatment cell lost again on the
   second candidate boot (`a2`). A single-cell, single-boot loss is `KILL-PENDING`, not a verdict: one boot
   at the 1 percent floor against up to 25 percent run-to-run variance cannot carry a KILL on its own.
   A KILL costs a setting its alternative, which is why it is the harder verdict to reach and why PROMOTE
   and KILL are not symmetric.
4. **PROMOTE**: better than both controls beyond the pooled margin in **every treatment cell** and no guard
   cell worse than both beyond its margin. The treatment cells are `d4-prose` and `d4-code`, except
   `SAMPLED_HEADS`, whose treatment cell is `d4-sampled` alone; every judged cell that is not a treatment
   cell is a guard.
5. Otherwise **INCONCLUSIVE**. A guard cell lost with no treatment cell lost is reported INCONCLUSIVE with
   the guard named: it bars a PROMOTE and is not a KILL.

**INCONCLUSIVE is reported, never retried into PROMOTE.** A large spread is itself the result: that cell
cannot resolve a change of that size on this box today.

## The eleven arms

Order: `docs/KNOB-COVERAGE.md`'s rank. `plan.tsv` is the list; the twelve-candidate cap lost one because
`TF_QMMF_HALF_BELOW` cannot be carried into the container by this launcher.

| # | setting | arm | class |
| --- | --- | --- | --- |
| 1 | `TF_FLASHNEXT_ATTN_LANES` | 0 to 1 | A1 |
| 2 | `TF_FLASHNEXT_DECODE_GRAPH` | 0 to 1 | A1 |
| 3 | `TF_FLASHNEXT_WINDOW_GRAPH` | 1 to 0 | A1 |
| 5 | `TF_FLASHNEXT_BATCH_DRAWS` | 1 to 0 | A1 |
| 6 | `TF_FLASHNEXT_SHARED_SIDE` | 1 to 0 | A1 |
| 7 | `TF_FLASHNEXT_SAMPLED_HEADS` | 1 to 0 | A1 |
| 8 | `TF_FLASHNEXT_KEEP_LATE` | 1 to 0 | A1 |
| 9 | `TF_FLASHNEXT_PROMPT_BF16` | 1 to 0 | A2 |
| 10 | `TF_FLASHNEXT_READOUT_ROWS` | 64 to 128 | A2 |
| 11 | `TF_FLASHNEXT_FACT_ROWS` | 64 to 128 | A2 |
| 12 | `TF_FLASHNEXT_WARM_AHEAD` | 1 to 0 | A2 |

`TF_QMMF_HALF_BELOW` (96 to 0) was the one that window lost: it ran under the pre-widening recipe filter,
which carried no plain `TF_*` name, so the preflight read it ABSENT and the coverage gate reported it
PASSAGE-LOST. The deployed launcher carries the `TF_*` class now, so the name is armable; until a window arms
it, its PASSAGE-LOST row stands.

What the cap left out, in rank order: `TF_FLASHNEXT_TABLE_WARM`, `TENSORFOLD_CUDA_KERNELS` (A3);
`TENSORFOLD_PREFIX_WAIT_MS`, `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS`, `TF_PROMPT_INTERMEDIATE`,
`TENSORFOLD_RESTORE_PREFETCH`, `TENSORFOLD_RESTORE_PREFETCH_GIB`, `TENSORFOLD_RESTORE_PREFETCH_MS` (A4).
The A4 group cannot be judged by this window's cells at all (they need a resume or two interleaved
conversations).

## The window's discipline

- The GPU lock is taken with `flock`; the 8-hour budget starts at **acquisition**, not at queue time.
  The window is capped at 11 candidates or 8 hours, whichever first.
- **The gate.** Before any boot, EnvBoot's fast r5 prompt-following verdict must be on disk as
  `~/work/EnvBoot/FAST-VERDICT` and must read CLEAN, and Main's `~/work/KnobScreen/GO` must exist. An
  absent marker is **not** CLEAN: the driver waits up to 20 minutes and then refuses, leaving production
  untouched.
- Production is stopped only after the lock and the gate, and restored on exit, gated on `/health` 200 and
  the pinned production image id (`PROD-IMAGE-OK`).
- The starter (`starter.sh`) waits for the same two markers **without holding the lock** and starts the
  window only then. A disarmed kit has no `GO` and no starter process (`install.sh --disarm` proves both).

## Acceptance of the rule and the instrument

`driver.sh dry` runs on the box before any GPU time and prints one line a check; the window may only run
after `DRY-OK`:

- the ref copy is taken from the pinned file and a tampered source is refused (`REF-SHA-MISMATCH`);
- a line the launcher cannot carry is commented by `basefilter.py`, listed, and its `unset` neighbour kept;
- `plan_gate` refuses a non-carried row (`PASSAGE-REFUSED`) and a row equal to the base (`PLAN-NO-OP`);
- `check_env.py` passes an `unset` line against absence, fails `PRESENT`, `ABSENT`, `VALUE` and `EXTRA`,
  and passes a name declared with `--allow-extra`;
- stub candidates produce PROMOTE, a two-cell KILL, `KILL-PENDING`, a confirmed KILL, an unconfirmed
  INCONCLUSIVE, a guard INCONCLUSIVE, an UNSTABLE INCONCLUSIVE and an inside INCONCLUSIVE; the pooled
  median is printed; a warm-up directory is never scored;
- `sens.py` reproduces the repo's own decision boundary: S0 PROMOTE, G8 and C20 INCONCLUSIVE;
- the starter is disarmed (no GO, no process).
