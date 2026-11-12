# Work meant for upstream TensorFold (`ashhart/TensorFold`): the order is not optional

This file is loaded on every request in this repo, by subagents too. The commands, the receipts and the reasons are
in `AGENTS.md`, section "Contributing upstream"; a subagent does not get that file, so pass it the section when you
delegate upstream work. Upstream's own rules outrank this summary: read `CONTRIBUTING.md`, `docs/atc/SKILL.md` and
`docs/pr/SKILL.md` at upstream's tip before each contribution.

1. **An issue exists before any edit.** Find it or open it (templates only: bug, feature, performance, proposal).
   A new family, backend or arithmetic change also needs the gate agreed on that issue.
2. **`atc check ISSUE --json` before choosing it.** Continue only on advice `free` or `yours`, and only when
   `complete` is true. Taken: offer to pair, split or review. Never open a competing implementation.
3. **`atc claim ISSUE --json` returns `claimed` before the first edit.** Keep the session number it returns; do not
   start a second session.
4. **Pulse only while really working** (`atc pulse ISSUE SESSION working --json`, every five minutes); `atc land`
   when work stops; `atc release` when the issue is given up.
5. **One behaviour a pull request**, cut from upstream `main`, on a branch of `BadAd84/TensorFold`. New things
   default off. No lossy format and no mode that changes output tokens, even opt-in.
6. **Before every push:** rebase on current `main`; run the checks as upstream's CI does (`tools/pr_check.py`, lean
   base against head with 0 new, the tests, `zig fmt --check`); then `atc overlap --json` last, and resolve every
   `"conflicts"` entry.
7. **Never force-push a branch under review.** Add a commit.
8. **Commits carry the owner's public identity only**, signed, with no AI attribution line, and no machine name,
   internal host, local path or private address in the diff, the commits or a receipt.
9. **Nothing is posted before the owner approved the exact text**: issue text, pull request title and body, every
   comment. The owner asking for work on an issue covers the ATC claim, pulses, landing and release for it.
