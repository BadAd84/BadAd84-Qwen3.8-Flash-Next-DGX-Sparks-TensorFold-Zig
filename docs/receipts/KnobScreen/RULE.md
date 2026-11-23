# The screen's decision rule, written before any row

Lane KnobScreen, 2026-11-23. This file is the rule the window is scored by. It was written and committed
before the first boot. Rows are in `out/`, the verdicts in `scores.tsv` and `RESULT.md`.

## What a screen is

All 78 settings the serve reads are now written in `scripts/qwen38/zig/target/env/dev.env`. The unmeasured
ones have never had a cell run against them on this stack. A five-level interleaved ABBA per setting is too
slow to spend on settings that will mostly be level, so this window is a **screen**: it sorts candidates into
PROMOTE, KILL and INCONCLUSIVE. **A screen is never a verdict.** A PROMOTE earns the full five-level A/B
later; it promotes nothing on its own, and nothing is written into `dev.env` by this lane.

## The subject: one setting changed, nothing else

- The image is the r5 FP4 dev serve the quality window used, pinned by id:
  `tensorfold-qwen38:qr-a-r5-1ece6e6db`, `sha256:001fc6ff0b5b7edfc3a992d34900122ac179e434ee05cec74f9afe8fdbd00063`
  (the same tag and id EnvBoot's dev boot gates on). No build in this window: env only.
- The base environment is the committed `dev.env`, sourced into the process that boots the serve.
- **The boot goes through the recipe launcher `$HOME/work/lanes/rpr/recipe/start.sh`, not `$HOME/qwen6-start.sh`
  (decided before the first row).** `qwen6-start.sh` `exec env`s a 56-name block of its own; measured against
  `dev.env` on the box, **7 of those 56 names are also in dev.env and all 7 carry the same value on both
  sides**, so that launcher would replace none of this file's settings. The reason for the recipe launcher
  is the other 49 names: it injects levers dev.env does not carry, and at least one of them is a value the
  campaign recorded as a losing alternative (`TF_FLASHNEXT_HC_Q12=1`, 1.02 GiB of copies, no gain outside
  noise, deliberately absent from dev.env). A screen of dev.env's settings must run on dev.env alone.
  The recipe launcher passes every `TENSORFOLD_*`/`TF_FLASHNEXT_*` name that is SET in its own environment
  (`start.sh:169-172` enumerates `env` for them), and a name written `export NAME` with no value is absent
  from `env`, so the two presence-default settings stay absent in the container, as they must.
- Boot arguments, identical for every boot: `PREPARE=0 IMAGE=<the pinned id tag> CHECKPOINT=nvfp4 VISION=0
  TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 PARALLEL=8 CONTEXT=262144 HOST=127.0.0.1 PORT=8888
  MEM_CHECK=0 THINKING=0 DRAFTS=1`. That is production's shape (8 lanes, 262,144 tokens, fp8 KV), which is
  the shape `dev.env`'s own `KV_PAGES=4096` note was written for.
- **`TENSORFOLD_CUDA_KERNELS=native` is required, not cosmetic.** Both images bake
  `TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121` into their ENV, and a *captured*
  kernel set refuses both `--kv-cache fp8` and paged KV (`cuda_lanes_load.zig:33` and `:35`, each testing
  `captured != null`), which are the two things this env sets. `native` makes `captured` null
  (`cuda/aot.zig:15-23`), after which both are allowed at TP=1 with no `--slide`. It is the same on every
  boot and is the one name the settings check exempts.
- An arm is a **copy of that file with exactly one line changed**. The driver asserts the old line occurs
  exactly once before it writes, and quotes the old line as a comment above the new one.
- A boot whose container environment does not carry every setting the arm's file states, at that value, is
  refused before its cells run (the settings check), retried once on a fresh boot, and then reported
  `INCOMPLETE`; it is never scored.
- Every boot is a fresh boot, and the serve is stopped between boots.

## Boots per candidate: control, candidate, control

Each candidate gets three boots in this order: **C-A-C** (control, candidate, control). One arm a boot. The
second control boot is not decoration: it is the null arm, and its disagreement with the first is the
spread every verdict is measured against.

`c1` = control boot 1, `a` = candidate boot, `c2` = control boot 2. A cell's value is `mid = (c1 + c2)/2`.

## The cells

Measured on every boot, in this order, by the tools' own outputs (no re-derivation from raw replies):

| cell | tool | how | value |
|---|---|---|---|
| `d1-prose` | `bench_concurrent.py` | chat prompt, 1 stream, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d1-code` | `bench_concurrent.py` | code prompt, 1 stream, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d4-prose` | `bench_concurrent.py` | chat prompt, 4 streams, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `d4-code` | `bench_concurrent.py` | code prompt, 4 streams, greedy, 256 tokens, 3 reps | median `aggregate_tps` |
| `c2k` | `ttft.py` | cold 2,048-token prompt, thinking off, idle, 3 reps, 16 max tokens | median TTFT (`cold2k-off`, idle) |
| `c32k` | `ttft.py` | cold 32,768-token prompt, thinking off, idle, 3 reps, 16 max tokens | median TTFT (`cold32k-off`, idle) |

The exact command lines, the seed (`--seed 1234`), the temperatures (`--temperatures 0,1.0`), the token
counts, the reps and the sizes are the spec string the digest is taken over, so no cell can differ between
arms by accident. `--alone --serial` are on: they give, per boot, the per-request token-sha comparisons
against the solo and non-drafting runs.

### Addendum, written before the first row (2026-11-23, after `docs/KNOB-COVERAGE.md` landed)

The coverage document's worklist named one setting whose read site only runs at temperature above zero:
`TF_FLASHNEXT_SAMPLED_HEADS` (sampled streams inside a shared round's batched head). A greedy-only cell set
cannot see it, so the window carries a seventh cell, measured on every boot beside the six:

| cell | tool | how | value |
|---|---|---|---|
| `d4-sampled` | `bench_concurrent.py` | chat prompt, 4 streams, temperature 1.0, seeded, 256 tokens, 3 reps | median `aggregate_tps` |

`d4-sampled` is **report-only for every candidate except `SAMPLED_HEADS`**: it appears in the table and in
`scores.tsv`, and its spread is computed, but it enters no verdict for the other eleven. For
`SAMPLED_HEADS` it is that candidate's **treatment cell**: the setting's read site cannot run in a greedy
cell, so its PROMOTE test is "better than both controls beyond the spread in `d4-sampled`, and no other cell
worse than its spread". The greedy cells are still guards for it.

The control requirement is unchanged: three boots a candidate, control, candidate, control.

**The text-change finding applies to the greedy cells only.** At temperature 1.0 a reply is a seeded draw;
a knob that reorders a float sum can change the draw without changing the arithmetic's intent, so
`d4-sampled`'s `alone`/`serial` comparisons are recorded and printed, never a finding.

**`DECODE_GRAPH` is screenable at TP=1.** The engine refuses `TF_FLASHNEXT_DECODE_GRAPH` with the dense split
only when `dense_split.applies()` is true, and `applies()` returns false at world != 2
(`cuda_dense_split.zig:35-36`); this serve is one rank, so the arm boots with `SPLIT_DENSE` untouched at its
committed 1. A boot refusal would still be a finding, not a result.

Directions: **higher is better** for the five `d` cells; **lower is better** for the two `c` cells.

## The digest, and what makes a boot a FINDING

A boot's `digest` is `sha256(sha256(bench_concurrent.py) + sha256(ttft.py) + spec)` where `spec` is the
cell spec string above. It is recorded in the boot's `meta.json`.

A boot is a **FINDING, not a result**, when any of these hold:

1. its digest differs from the control boot's digest;
2. any cell's `prompt_tokens` differs from the control's for the same cell (the same prompt must be sent);
3. `boot_rc` is not 0, or `/health` is not 200, or `/v1/models` names no model, after one fresh retry;
4. a measured cell reports `failed` or `unmeasured` above zero;
5. the server log carries a request from a client that is not `127.0.0.1` (foreign traffic);
6. a `d` cell's `alone` comparison returns `unequal` above zero, or its `serial` comparison returns
   `unequal` above zero: the greedy text changed, so the arm is not a speed result until that is explained.
   A `vacuous` alone/serial check is reported and is not a finding.

A candidate with a FINDING on any of its three boots gets **no verdict**: it is reported
`INCONCLUSIVE-FINDING` with the finding named, and the window moves on. A finding is never retried into a
verdict.

## The spread, and the verdict

For each cell `i`, with the two control boots' values `c1_i` and `c2_i`:

```
mid_i   = (c1_i + c2_i) / 2
s_i     = |c1_i - c2_i| / mid_i          the cell's control-to-control spread, in the same window
m_i     = max(s_i, 0.01)                 the margin every test uses: the spread, floored at 1 percent
delta_i = (a_i - mid_i) / mid_i          positive = more throughput; for c cells negative = faster
```

**The 1 percent floor is the resolvability floor, and it was added before any row after a check against the
repo's own numbers** (`work/KnobTest`, `work/ProseDraft`). On the shared-drafts receipt
(`work/ProseDraft/RESULT.md:68-84`) the repeat arms B0 and C0 read 207.8 and 207.6 at prose 4 streams, a
0.1 percent spread, while G8 at 207.3 and C20 at 207.9 are recorded **level**. A rule with no floor kills G8
at minus 0.24 percent, a quarter of a percent it cannot attribute, and that KILL would remove a setting from
the worklist on the thermometer. With the floor, the same three arms come out exactly as the receipt does:
S0 plus 10.2 percent **PROMOTE**, G8 **INCONCLUSIVE**, C20 **INCONCLUSIVE** (`work/KnobScreen/sensitivity/`,
`sens.py`). So a difference inside the floor is level, never a KILL and never a PROMOTE.

With `m_i = max(s_i, 0.01)`:

- **better than both, beyond the margin**: `a_i > c1_i * (1 + m_i)` and `a_i > c2_i * (1 + m_i)` for a `d`
  cell; `a_i < c1_i * (1 - m_i)` and `a_i < c2_i * (1 - m_i)` for a `c` cell.
- **worse than both, beyond the margin**: `a_i < c1_i * (1 - m_i)` and `a_i < c2_i * (1 - m_i)` for a `d`
  cell; `a_i > c1_i * (1 + m_i)` and `a_i > c2_i * (1 + m_i)` for a `c` cell.

Verdicts, in this precedence:

1. **FINDING** (any of the six above) -> `INCONCLUSIVE-FINDING`.
2. **UNSTABLE** -> `INCONCLUSIVE`: any raw spread `s_i > 0.25` over the seven cells. The controls disagree with each
   other by more than a quarter in a cell, so nothing about the candidate can be read from this window.
3. **KILL**: worse than both controls beyond the margin in **any judged cell**. A judged cell is every
   measured cell except a report-only one.
4. **PROMOTE**: better than both controls beyond the margin in **every treatment cell** and no guard cell
   worse than both beyond its margin. A candidate's treatment cells are `d4-prose` and `d4-code`, except
   `SAMPLED_HEADS`, whose treatment cell is `d4-sampled` alone (addendum above); every judged cell that is
   not a treatment cell is a guard.
5. Otherwise **INCONCLUSIVE** (inside the spread).

KILL is evaluated before PROMOTE on purpose: a setting that gains at four streams and loses beyond the spread
anywhere else is not a promotable setting.

For the eleven candidates other than `SAMPLED_HEADS`, `d4-sampled` is report-only: it appears in the table
and `scores.tsv` with its spread, and it enters neither KILL nor the guards. It is still a **finding** source
(a failed or unmeasured request, or a prompt-token mismatch, refuses the boot for any cell). `INCONCLUSIVE`
names the treatment cells that were inside the spread.

**INCONCLUSIVE is reported, never retried into PROMOTE.** A large control spread is itself the result: it says
the cell cannot resolve a change of that size on this box today.

## Budget and ordering

The window is capped at **12 candidates or 8 hours**, whichever first. Candidates are ordered by how directly
the read site sits in a decode or prompt round, interleaved so a long-shot does not follow a promising one on
a cooling GPU. Whatever the cap leaves out is named in `RESULT.md`; it is stage two's input, not a gap.

## The window's discipline

- The GPU lock is taken with `flock` and waited on; the 8-hour budget starts at **acquisition**, not at queue
  time. The window runs FIFO behind the lanes already queued.
- **The gate.** Before any boot, EnvBoot's fast r5 prompt-following verdict must be on disk as
  `~/work/EnvBoot/FAST-VERDICT` and must read CLEAN (Main's 2026-11-23 arrangement: boot proof and a
  200-item screen first, lock released, the 1,664-item run later). An absent marker is **not** CLEAN: the
  driver waits up to 20 minutes and then refuses the window, leaving production untouched. A marker that
  does not read CLEAN blocks the window, and `RESULT.md` reports its numbers. A speed screen on a build that
  fails prompt following measures nothing.
- A **preflight boot with its cells** must pass before the first arm, so a wrong serve shape costs one boot
  instead of thirty-six.
- Production is stopped only after the lock and the gate, and restored on exit, gated on `/health` 200 and
  the pinned production image id (`PROD-IMAGE-OK`).

## Acceptance of the rule itself

The driver is dry-run against a stub before the window: the stub boot writes the same `meta.json`,
`conc.json` and `ttft.txt` fields the real tools write, and the analyzer must read them and print a table
before any GPU time is spent. A stub candidate for each branch (promote-shaped, kill-shaped, inside the
spread) must produce that branch.
