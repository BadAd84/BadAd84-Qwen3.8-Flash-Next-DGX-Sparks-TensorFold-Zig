#!/usr/bin/env python3
"""Verify the production env record against its own evidence, independently of gen.py.

Checks, each printed as a line:

  rows        the derived table's names equal the served binary's own name list (strings-P.txt, the
              parity window's phase-0 scan) plus the vision helper's TENSORFOLD_VIDEO_TOKENS, and
              prod.env states exactly the table's names, and the register carries one tagged verdict
              for each.
  citations   every setting in prod.env has a `# Cite: <path>:<line>` within the eight lines above it
              (the same window check-dev-env.py applies to dev.env); the cited file exists and the
              cited line contains the setting's name.
  launcher    prod-launcher.env states exactly the 54 names live-env.txt captured, at the same values.

Run from the repo root: python docs/receipts/ProdEnvAudit/check-prod-rows.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
EVID = ROOT / "docs/receipts/ProdEnvAudit"
PROD = ROOT / "scripts/qwen38/zig/target/env/prod.env"
REGISTER = ROOT / "scripts/qwen38/zig/target/env/register.env"
TABLE = EVID / "prod-settings-table.zig"
LAUNCHER_VIEW = EVID / "prod-launcher.env"
LIVE = EVID / "live-env.txt"
ORACLE = EVID / "strings-P.txt"
HELPER = {"TENSORFOLD_VIDEO_TOKENS", "TENSORFOLD_VISION_WEIGHTS"}
CREATE = re.compile(r"^#\s*Cite:\s*((?:docs|work|int-docs|scripts)/[A-Za-z0-9_./-]+:\d+)\s*$")
CITE_ANY = re.compile(r"((?:docs|work|int-docs|scripts)/[A-Za-z0-9_./-]+)")
SETTING = re.compile(r"^(?:export ([A-Z0-9_]+)=|unset ([A-Z0-9_]+)$)")
ROW = re.compile(r'\.\{ \.name = "([A-Z0-9_]+)"')
VERDICT = re.compile(r"^#\s*prod\s+(?:default-ok|debt|unreachable|measured|inert|raw|launcher|absent|candidate|retired)\s+([A-Z0-9_]+)\s*:")


def fail(msg: str) -> int:
    print(f"CHECK-FAIL {msg}")
    return 1


def main() -> int:
    rc = 0
    table = {m.group(1) for m in (ROW.search(l) for l in TABLE.read_text(encoding="utf-8").splitlines()) if m}
    oracle = set(ORACLE.read_text().split())
    expected = oracle | HELPER
    lines = PROD.read_text(encoding="utf-8").splitlines()
    prod = {}
    at = {}
    for i, line in enumerate(lines):
        m = SETTING.match(line)
        if m:
            name = m.group(1) or m.group(2)
            if name in prod:
                rc = fail(f"prod.env states {name} twice")
            prod[name] = line
            at[name] = i
    verdicts = {m.group(1) for m in (VERDICT.match(l) for l in REGISTER.read_text(encoding="utf-8").splitlines()) if m}
    if table == expected and set(prod) == table and verdicts == table:
        print(f"rows: table {len(table)} = binary {len(oracle)} + helper {len(HELPER & table)}; "
              f"prod.env {len(prod)}; verdicts {len(verdicts)}; set-equal yes")
    else:
        rc = fail(f"set mismatch: table-only {sorted(table - expected)} expected-not-table {sorted(expected - table)} "
                  f"prod-only {sorted(set(prod) - table)} table-not-prod {sorted(table - set(prod))} "
                  f"verdict-only {sorted(verdicts - table)} table-not-verdict {sorted(table - verdicts)}")

    uncited, unresolved, nameless = [], [], []
    for name, line in prod.items():
        window = lines[max(0, at[name] - 8):at[name]]
        if not any(CITE_ANY.search(l) for l in window):
            uncited.append(name)
            continue
        # The row's own citation is the nearest `# Cite:` line above it; an earlier block in the same
        # eight-line window is another setting's.
        cites = [m.group(1) for l in window if (m := CREATE.match(l))]
        if not cites:
            uncited.append(name)
            continue
        cite = cites[-1]
        path_s, _, lineno = cite.rpartition(":")
        path = ROOT / path_s
        if not path.is_file():
            unresolved.append(f"{name} -> {cite} (no such file)")
            continue
        cited = path.read_text(encoding="utf-8", errors="replace").splitlines()
        if int(lineno) > len(cited):
            unresolved.append(f"{name} -> {cite} (only {len(cited)} lines)")
        elif name not in cited[int(lineno) - 1]:
            nameless.append(f"{name} -> {cite}")
    print(f"prod-env: {len(uncited)} setting(s) without a citation")
    for name in uncited:
        rc = fail(f"UNCITED {name}")
    for item in unresolved:
        rc = fail(f"UNRESOLVED {item}")
    for item in nameless:
        rc = fail(f"CITED-LINE-LACKS-NAME {item}")
    if not unresolved and not nameless:
        print(f"citations: {len(prod)}/{len(prod)} resolve; {len(prod)}/{len(prod)} cited lines contain the name")

    live = {}
    for line in LIVE.read_text(encoding="utf-8").splitlines():
        if line.strip():
            name, _, value = line.partition("=")
            live[name] = value
    view = {}
    for line in LAUNCHER_VIEW.read_text(encoding="utf-8").splitlines():
        if line.startswith("export "):
            name, _, value = line[len("export "):].partition("=")
            view[name] = value
    if view == live:
        print(f"launcher: view {len(view)} = captured {len(live)}; values equal yes")
    else:
        rc = fail(f"launcher view differs: only-view {sorted(set(view) - set(live))} "
                  f"only-live {sorted(set(live) - set(view))} "
                  f"value-diff {sorted(n for n in set(view) & set(live) if view[n] != live[n])}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
