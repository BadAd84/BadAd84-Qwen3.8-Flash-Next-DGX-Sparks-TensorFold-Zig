# The env register: a verdict for every setting the serve reads

`scripts/qwen38/zig/target/env/register.env` exists because a newer base can carry a default-on
decision that appears in no env file, and leaving it unset silently inherits its cost. It happened:
upstream added `shared_stop = 0.6` on 2026-11-10, which limits greedy drafting beside another open
stream. Production's engine predates it, so production drafted 3.03 tokens a round while ours drafted
1.92, and the difference read as an engine gap. Turning the gate off is worth 7 to 11 percent at two
to eight streams and closed 54 percent of the prose gap (`work/ProseDraft/RESULT.md`). Neither
`dev.env` nor `prod.env` names the setting, so no name-level sweep could find it.

## What the register is

The engine's own table, `zig/src/platform/environment.zig`, is the authoritative list of settings:
every rule whose scope the Flash Next serve reads (`flashnext`, `cuda`, `common`). Each such setting
must hold one of four verdicts:

| verdict | where | meaning |
|---|---|---|
| carried | `dev.env` `export NAME=value` | we set it, and `check-dev-env.py` requires a measured citation above it |
| default-ok | `register.env` `# default-ok NAME:` | we keep the engine default, and we measured it level or better with evidence |
| debt | `register.env` `# debt NAME:` | unmeasured on our stack: counted, and each is a lead |
| unreachable | `register.env` `# unreachable NAME:` | the path cannot run on this serve, with the reason |

A setting with no verdict is SILENT, and `check-env-coverage.py` fails on it. A verdict naming a
setting the table no longer has is STALE and fails too, so the register cannot rot. Debt is measured
debt, not permission: the count is printed on every run and should fall.

## At every re-seat

1. `python scripts/qwen38/zig/target/env/update-env-register.py --table <new tree>/zig/src/platform/environment.zig`
   keeps every existing verdict and appends a `debt` line for each setting the table now has and we
   do not name. A new upstream knob therefore lands as a visible entry instead of a silent default.
2. `python scripts/qwen38/zig/target/env/check-env-coverage.py --table <tree>/zig/src/platform/environment.zig --strict-carried`
   from the tree we actually serve, so a `dev.env` export with no reader in that tree also fails.
3. Measure what the new entries need; promote a winner into `dev.env` with its citation, or record a
   measured `default-ok`.

The register was generated against upstream main `7bd7081e0` with 65 settings in scope: 5 carried,
60 debt, 0 silent. The nine exports that main's table does not have are our series' own settings and
production-engine-only names; each is checked for a reader when the gate runs with `--strict-carried`
against the served tree.
