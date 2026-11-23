# Promotion rules for env rows and launcher options

Read this before touching an env file, a boot script or a queue. It exists because a measured setting is only worth
anything once it is in the tree every later boot inherits, and because two of our serve repos drifted: a knob measured
better stayed a per-arm flag, and a setting production runs stayed off in every arm, so the cells described a serve
nobody ships.

## The rule, in one paragraph

Every setting the served engine reads is set explicitly, and every measured winner is promoted into the default path -
env file or launcher - in the commit that carries its cells. Nothing that won stays a flag a queue has to remember. A
cell measured before a promotion and a cell measured after it describe two different serves, and any table that mixes
them says so.

## Env rows

- **Complete.** Every row of the served engine's settings table whose scope this serve reads is SET in both env files
  (`prod.env` and `dev.env`, or whatever they are called here), at a measured value or at the engine's own default
  written down. "Unset" is not a value: the engine's default may change in a rebase and take the serve with it.
- **One verdict a row**, in the register, with an evidence path on every line:
  - `measured NAME=VALUE` - a measurement chose it; the cells are in the settings ledger.
  - `inert NAME=VALUE` - examined, and it cannot be a lever on this serve: a log or receipt switch, a limit of a path
    this serve never runs (vision, PDF, another model family), or plumbing. The reason is the record; it is what stops
    the row being asked about again.
  - `debt NAME=VALUE` - set to the engine default and not measured here. A lead, never permission.
  - `raw NAME=VALUE` - read through a raw getenv, so the table has no row.
  - `launcher NAME=` - the boot script computes it per boot (rank, world, parallel, reserve); setting it would override
    the launcher.
  - `absent NAME=` - no value is the decision (no key file, no ceiling), and the register says what the absence means.
  - `candidate NAME=VALUE` - a dev-only override, see below.
- **`dev.env` is `prod.env` plus candidates.** A candidate may only raise a row that `prod.env` keeps at the engine's
  default, and it may not repeat prod's value (that decides nothing). A candidate that overturns a measured line is a
  finding, not a test.
- **Promotion is a move, not an edit in place.** The candidate line moves into the recipe section of BOTH env files, the
  register line becomes `measured` with the evidence, and all of it lands in the commit that carries the cells.

## Launcher options - the same rule, and the same mistakes

A boot script carries options that are not table rows: paths, drafter bits, parallel and context, the disk-tier switch,
profiling wrappers. **They follow the identical rule**: if a measurement shows an option is better, it becomes the
launcher's DEFAULT. A promotion that only sets the flag in a few queues is not a promotion.

The mechanics, learned the hard way:

1. **Change the default in the launcher, and in every driver that forwards it.** A wrapper that expands
   `SOMETHING='${SOMETHING:-0}'` into the launcher's environment silently overrides a new default of 1. Both must change
   in the same commit, or the promotion is invisible on the next boot.
2. **Rewrite the launcher's own test to the new contract.** A test that asserts "unset adds nothing" encodes the old
   default; after promotion it must assert "unset adds the promoted value", and the off-arm case must be `SOMETHING=0`.
   A promotion that leaves that test unchanged either fails it or, worse, passes because nothing was wired.
3. **Run the repo's sync gate before the next GPU window.** The launcher you edited lives in the repo; the box runs a
   copy. A stale copy made a day of cells measure another decode path once already.
4. **Record the promotion where the settings ledger lives**: the option, its value, the evidence, the date. Then
   re-measure any comparison table whose cells predate it.

## The worked example: the disk tier

- Production ran the NVMe/disk KV tier (`--learn-conversations --learn-gib 128 --learn-daily-gib 512
  --learn-min-free-gib 40`, upstream PR #1411).
- The Zig launcher carried the same tier behind `LEARN`, defaulting to 0, and only two purpose-built queues ever set it.
  Every screen and A/B booted without it, so the cells were comparable to production only at short prompts where nothing
  is kept, and not at long context, on a resume, or across a restart.
- The tier was measured not slower at any level, and it is what production runs, so it was promoted: default 1 in the
  launcher, default 1 in the forwarding driver, the launcher's test rewritten to assert the promoted default, the sync
  gate run, and the promotion recorded. Every later arm inherits it.

## The promotion checklist

1. The cells exist for the full set of stream counts (1, 2, 4, 6 and 8, a fresh boot a level, interleaved arms), and
   replies are equal to the control's unless the change is meant to alter them.
2. No level regresses. A change that gains somewhere and loses elsewhere is a trade: it goes to the owner with both
   sides, never into the default by discretion.
3. The default changes in the launcher and every forwarding driver, in one commit.
4. The launcher's test asserts the new default and the off arm.
5. The register (or the settings ledger) records the value with its evidence.
6. The gates run: the env files agree and cover every row, the launch test passes, the sync gate is green.
7. Any table of cells that predates the promotion is marked as such, or re-measured.
