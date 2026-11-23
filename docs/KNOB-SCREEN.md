# The knob screen: the rule, the eleven arms, their verdicts

Current state of the screen lane. The kit is tracked in the repo at `scripts/qwen38/zig/target/screen/`:
`driver.sh`, `analyze.py`, `basefilter.py`, `check_env.py`, `mkenv.py`, `stub_cells.py`, `rec.py`,
`result.py`, `sens.py`, `plan.tsv`, `allow-extra.txt`, `install.sh`, `starter.sh`, `fetch.sh`, `RULE.md`.
`install.sh` copies the kit to the box and pins the committed `dev.env`'s sha256; the driver refuses a copy
whose sha differs. `docs/receipts/KnobScreen/` holds the pre-fix copies of the four files this page cited
when the kit lived under `work/`, plus the evidence this page now cites: the pre-fix preflight's container
env and settings mismatch, the coverage gate's passage output, and the box's dry-run transcript. The raw
boot records and the arms' own outputs live on the box under `work/KnobScreen/out/`.

Status as of 2026-11-23, after the review's section 2: **disarmed, not run, dry green.** The kit changed in
six ways, each proven by a stub proof in the box's dry run (`docs/receipts/KnobScreen/dry-run-2026-11-23.txt`,
`DRY-OK 47`):

- **The base is the committed `dev.env`, copied at start with its sha256 recorded.** The copy is verified
  against the pin `install.sh` wrote (`refcommitted/dev.env.sha256`) and every boot records it as `env_sha`,
  so a stale `ref/` cannot become a window's base. The previous `ref/dev.env` was a stale copy that predated
  the register correction.
- **The base is what the recipe launcher can carry.** Its `-e` list comes from
  `env | grep -E '^(TENSORFOLD|TF_FLASHNEXT)_'` when this kit was built, so 74 value lines were live and 26
  plain `TF_*` lines were not. The launcher forwards `TF_` too since 2026-11-23, so a re-arm must widen this
  kit's `plan_gate` filter and its base together; until then the 26 stay commented in the materialised base,
  listed in `out/base-not-carried.txt`, and cannot be an arm: `plan_gate` refuses such a row
  (`PASSAGE-REFUSED`), and the coverage gate fails it while the filter is narrow (`PASSAGE-LOST`; its output is
  `docs/receipts/KnobScreen/coverage-passage-2026-11-23.txt`, 26 names, exit 1).
- **Arm 4 is removed.** `TF_QMMF_HALF_BELOW` is one of those 26; the 15:44Z preflight read it ABSENT and
  the window refused. The screen is eleven arms, not twelve.
- **KILL is no longer a one-cell, one-boot verdict.** It needs a treatment cell worse than both controls
  beyond the margin **and** corroboration: a second judged cell lost in the same boot, or the same cell lost
  again on a second candidate boot (`a2`). A single-cell loss is `KILL-PENDING`, and the driver boots the
  candidate once more before the window reports it.
- **The spread is pooled over every control pair in the window**, not one pair: the margin is the median of
  the per-arm control spreads for that cell, floored at 1 percent. A pair more than 25 percent apart makes
  only its own arm inconclusive.
- **The first boot is a discarded warm-up, and every boot is primed** with one short request before its
  cells, so no cell is the first traffic after a fresh boot.
- **`check_env.py` teaches `unset` and fails `EXTRA`.** `unset NAME` is an absence test; a name in the
  container that the arm does not state fails unless it is declared in `allow-extra.txt`, whose eight
  entries are the recipe `config.sh` defaults measured from the container's own Config.Env.
- **The starter is disarmed.** No `GO` file, no starter process; `install.sh --disarm` removes both and
  proves both, and the dry run repeats the proof.

The two attempts at a window today (13:56Z and 15:44Z) both stopped at preflight: the base they booted
stated 21 plain `TF_*` values the launcher cannot carry, the settings check refused, production was restored
(`PROD-IMAGE-OK`), and nothing was measured. Those boots are preserved in
`work/KnobScreen/out.failed-2026-11-23T1546/`. **No arm has booted and there are no verdicts.** The rows are
owed by the GPU queue, not by the instrument. A screen is never a verdict: a PROMOTE only earns the
five-level A/B later, and **nothing here is written into `dev.env`**.

## Why a screen

`docs/KNOB-COVERAGE.md` classifies all 95 settings the served tree reads and lists 20 UNMEASURED ones
whose read site can move decode or prompt speed. The repo's five-level interleaved ABBA gives one
setting a real verdict, but it costs five boots a level and is too slow to spend on twenty settings that
will mostly be level.

So the 20 are screened first: a discarded warm-up, then three boots a candidate (control, candidate,
control), one arm a boot, and a rule decided in advance that sorts each candidate into PROMOTE, KILL,
KILL-PENDING or INCONCLUSIVE. The window is capped at 11 candidates or 8 hours. The settings after the cap
stay on the worklist, untouched and unjudged.

## The rule, in one page

The full rule is `scripts/qwen38/zig/target/screen/RULE.md`. In short:

- **Subject.** The r5 FP4 dev image, pinned by id
  (`tensorfold-qwen38:qr-a-r5-1ece6e6db`, `sha256:001fc6ff...`), booted through the recipe launcher with
  the carried base. A candidate's copy differs in **exactly one line**, asserted by the writer before it
  boots and verified after. Nothing is built.
- **Boot arguments.** Production's shape, identical on every boot: 8 lanes, 262,144 tokens, fp8 KV,
  vision off, drafts on, loopback only. `TENSORFOLD_CUDA_KERNELS=native` is in that list because both
  images bake `TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121` into their ENV, and a
  captured kernel set refuses both `--kv-cache fp8` and paged KV (`cuda_lanes_load.zig:33,35`), which are
  exactly what this env sets; `native` clears `captured` and both are then allowed at TP=1.
- **Boots.** One discarded warm-up boot before the first arm, then three a candidate in the order control,
  candidate, control. The second control is the null arm. A `KILL-PENDING` earns one more candidate boot
  (`a2`) before the window calls it a KILL.
- **Cells.** Decode at 1 and 4 streams on the prose and code prompts at temperature 0 (greedy, 256
  tokens, 3 reps, `aggregate_tps`); one sampled 4-stream cell at temperature 1.0 (the only cell that
  reaches `SAMPLED_HEADS`); cold TTFT at 2k and 32k (thinking off, idle, 3 reps).
- **Spread and margin.** Per cell and arm, `s_pair = |c1 - c2| / ((c1 + c2)/2)`. The cell's spread `s` is
  the median of those pairs over every arm in the window, and every test uses `m = max(s, 0.01)`. The 1
  percent floor is the resolvability floor, added before any row after checking the rule against
  `docs/receipts/ProseDraft/RESULT.md`'s own numbers: at that receipt's 0.1 percent repeat spread a rule
  with no floor kills an arm it records as level at minus 0.24 percent.
- **Verdicts, in precedence.** FINDING (digest, prompt tokens, boot, health, foreign traffic, or greedy
  text changed) - no verdict. UNSTABLE (this arm's pair spread, or the pooled spread, above 25 percent) -
  INCONCLUSIVE. KILL (a treatment cell worse than both controls beyond the margin, corroborated). PROMOTE
  (better than both beyond the margin in every treatment cell, no guard cell worse). KILL-PENDING (one
  treatment cell lost in one boot, no corroboration yet) - not a verdict. Otherwise INCONCLUSIVE.
- **A guard loss is not a KILL.** A guard cell worse than both controls bars PROMOTE and is reported
  INCONCLUSIVE with the cell named; only a treatment cell can carry a KILL.
- **INCONCLUSIVE is reported, never retried into PROMOTE.** A large control spread is itself the result:
  that cell cannot resolve a change of that size on this box today.

## The eleven arms

The order is `docs/KNOB-COVERAGE.md`'s rank, truncated at the 11-candidate cap the passage rule leaves: the
seven A1 per-round leads the launcher can carry, then the four A2 prompt-pass leads.

| # | setting | arm | class | why it is here |
| --- | --- | --- | --- | --- |
| 1 | `TF_FLASHNEXT_ATTN_LANES` | 0 to 1 | A1 | a shared round's attention in one launch a kernel; the 1.2.6 stack measured 0 to 2 percent alone and 3.1 stacked, and this stack has it off |
| 2 | `TF_FLASHNEXT_DECODE_GRAPH` | 0 to 1 | A1 | one bounded decode round as a CUDA graph; legal at TP=1 because the dense-split refusal needs `applies()`, false at world != 2 |
| 3 | `TF_FLASHNEXT_WINDOW_GRAPH` | 1 to 0 | A1 | drafted windows and head pieces eager instead of replayed graphs; capture cost against replay saving is unmeasured |
| 5 | `TF_FLASHNEXT_BATCH_DRAWS` | 1 to 0 | A1 | per-stream row draws instead of batched; a launcher value never A/B'd on this stack |
| 6 | `TF_FLASHNEXT_SHARED_SIDE` | 1 to 0 | A1 | shared expert inline after the routed experts instead of on its own stream |
| 7 | `TF_FLASHNEXT_SAMPLED_HEADS` | 1 to 0 | A1 | sampled streams drafted separately; judged on the sampled cell, which is why the window carries one |
| 8 | `TF_FLASHNEXT_KEEP_LATE` | 1 to 0 | A1 | pending DeltaNet rows re-run instead of kept in a log; one GPU only, so a decode effect at one stream |
| 9 | `TF_FLASHNEXT_PROMPT_BF16` | 1 to 0 | A2 | the other prompt path instead of BF16 prompt tiles |
| 10 | `TF_FLASHNEXT_READOUT_ROWS` | 64 to 128 | A2 | read-out fused tiles from 128 rows instead of 64 |
| 11 | `TF_FLASHNEXT_FACT_ROWS` | 64 to 128 | A2 | NVFP4 prompt tiles from 128 rows instead of 64 |
| 12 | `TF_FLASHNEXT_WARM_AHEAD` | 1 to 0 | A2 | PLE warm-ahead hints off instead of on |

Every arm's value differs from the committed `dev.env`'s own value; `plan_gate` refuses a row that does not
(`PLAN-NO-OP`), because that arm would silently measure the control twice.

**The base is dev.env's 95 settings: every row of the served r5 tree's table, not the series tree's 78.** Of
them, 74 value lines reach the container through the recipe launcher and 26 plain `TF_*` lines do not; the
26 are listed in the base's report and are absent on every boot, so no arm sets one. The 19
rows the r5 patches add (`GATHER_READ`, `GATHER_DIRECT`, `GATHER_EARLY`, `GATHER_THREADS`, `GATHER_LOG`,
`GATHER_LOCK_SCALES`, `GATHER_CACHE_MIB`, `PROMPT_GEMM2`, `PROMPT_MX128`, `PROMPT_SYNC`, `FUSED_SPLIT`,
`READOUT_FUSE`, `HEAD_PIECE`, `PREFILL_TAIL`, `ROUND_MS`, `DRAFT_ROW_MS`, `DRAFT_AHEAD`, `PROMPT_SHARED_DIRECT`,
`WINDOW_CHECK`) are stated in `dev.env` since `c70f8d13`, each with the served tree's read site and value, and
their verdicts are in `docs/KNOB-COVERAGE.md`'s 19-row section and the patch READMEs. No arm of this window sets
any of them, so they are equal on every arm, which is what makes the C-A-C deltas attributable.
(Measured: `work/QRerun/trees/fp4/src/zig/src/platform/environment.zig` carries 95 rows in scope and the
gate reads `coverage: 95 settings in scope, set 95`; the series tree `work/Int4Step5/tree` carries 78 and is not
the table this serve validates.)

What the cap left out, in rank order: `TF_QMMF_HALF_BELOW` (the passage casualty: no launcher route, so it
cannot be an arm until one exists); `TF_FLASHNEXT_TABLE_WARM`, `TENSORFOLD_CUDA_KERNELS` (A3);
`TENSORFOLD_PREFIX_WAIT_MS`, `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS`, `TF_PROMPT_INTERMEDIATE`,
`TENSORFOLD_RESTORE_PREFETCH`, `TENSORFOLD_RESTORE_PREFETCH_GIB`, `TENSORFOLD_RESTORE_PREFETCH_MS` (A4).
They are stage two's worklist; none of them was measured or touched. The A4 group is cache and resume
tuning and cannot be judged by this window's cells at all (they need a resume or two interleaved
conversations), which is why the cap costs least there.

## The instrument

- `scripts/qwen38/zig/target/screen/driver.sh` takes the GPU lock with `flock`, prepares the base, the
  passage gate and the plan gate **before anything is booted or stopped**, and refuses to screen until
  EnvBoot's r5 prompt-following verdict is on disk as `CLEAN` and `~/work/KnobScreen/GO` exists. It stops
  production only after the lock and the gate, runs the discarded warm-up, then the C-A-C boots (plus `a2`
  only on `KILL-PENDING`), then restores production and checks `/health` 200 against the pinned production
  image id (`PROD-IMAGE-OK`). Budget starts at lock acquisition, not at queue time.
- **The base is traceable to the committed file.** `install.sh` copies the committed `dev.env` to
  `refcommitted/dev.env` and writes its sha256 beside it; the driver copies that to `ref/dev.env`, records
  the sha in `out/ref.txt` and in every boot's `meta.json` (`env_sha`), and refuses a copy whose sha differs.
- **The launcher is the recipe's `start.sh`, not `$HOME/qwen6-start.sh`.** The dev serve's launcher
  `exec env`s a 56-name block of its own. Measured against `dev.env`: 7 of the 56 are also in dev.env and
  all 7 carry the same value on both sides, so it would replace none of this file's settings. It is not the
  base because of the other 49: it injects levers dev.env does not carry, including `TF_FLASHNEXT_HC_Q12=1`,
  which dev.env records as a measured negative and deliberately omits. The recipe passes every
  `TENSORFOLD_*`/`TF_FLASHNEXT_*` name that is set in its environment and nothing else; its
  `scripts/config.sh` also exports eight defaults of its own, which `allow-extra.txt` declares with the
  `config.sh` line for each, so `check_env.py` can still fail a name nobody declared.
- **Every boot proves the environment is the arm's.** `check_env.py` compares the container's own
  environment with the arm: a missing name, a different value, a `unset` name that is present, or a name the
  arm does not state (unless declared) refuses the boot before its cells run and retries once on a fresh
  boot. That is what stops a screen from scoring a control twice.
- **The rule was checked against the repo's own verdicts before the first row.**
  `scripts/qwen38/zig/target/screen/sens.py` feeds the rule the shared-drafts receipt's measured 4-stream
  numbers (`docs/receipts/ProseDraft/RESULT.md:68-84`) in the writers' shape and asserts the verdicts: S0
  (plus 10.2 percent) PROMOTE, G8 (minus 0.2 percent) and C20 (plus 0.1 percent) INCONCLUSIVE. Without the
  floor, G8 was killed at minus 0.24 percent against a 0.1 percent control spread, which is why the floor
  exists in the rule.
- **The dry run precedes the window.** `driver.sh dry` writes stub boots in the exact shape the clients
  write (`conc.json` cells with `alone`/`serial`/`reps[].requests[].prompt_tokens`; `ttft.py`'s summary
  lines) and proves each fixed check: the ref sha and a tampered source, the base filter's comment and
  report, the passage gate and the no-op gate, `unset`/`PRESENT`/`ABSENT`/`VALUE`/`EXTRA` and a declared
  allowlist, PROMOTE / two-cell KILL / KILL-PENDING / confirmed KILL / unconfirmed INCONCLUSIVE / guard
  INCONCLUSIVE / UNSTABLE / inside, a malformed boot that becomes `INCONCLUSIVE-FINDING` without touching
  the other arms, the pooled median, a warm-up directory that is never scored, the
  sensitivity cases, the coverage gate's passage self-test, the real plan against the installed env, and
  the disarmed starter. It prints one line a proof and ends `DRY-OK 47` on the box.

## The window

When the window has run, `work/KnobScreen/out/RESULT.md` on the box holds the per-candidate table, the
spreads, the pooled margins and the end state, and `work/KnobScreen/out/scores.tsv` the machine-readable
rows; the boot records live beside them under `out/<arm>/<role>/`. Neither exists yet, so neither is tracked
in `docs/receipts/`.
