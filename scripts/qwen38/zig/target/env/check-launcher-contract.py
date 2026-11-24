#!/usr/bin/env python3
"""Assert the dev launcher's defaults against the environment of record, and each off arm's delivery.

One launch contract, two files: the dev launcher (scripts/qwen38/zig/qwen6-start.sh) states the
defaults it carries in its own `exec env` block, and dev.env is the launcher env a boot is armed with
(check-env-coverage.py's own words). This gate takes every promoted row of dev.env - a row the
register does not mark `retired` - and requires one of three documented states for it, all three
proven rather than assumed:

  launcher   the launcher's exec env block states NAME, and its value is the value dev.env states. A
             different value fails. The one exception is a name the register marks `launcher`: there
             the boot script decides, and the gate prints the row as a NOTE with the register's line
             rather than failing it (today TF_FLASHNEXT_PRODUCT_STREAMS, which the recipe computes
             at 5 and the launcher overrides at 8).
  default    the launcher leaves the name alone and dev.env's own comment block documents it as the
             engine's own default, writing the value out: `default <value>: <read site>`. The
             documented value must be the row's value, so a doc saying `default 0` above a row set to
             1 fails; `blank` and `absent`/`is the absence itself` are the forms of a blank value and
             of `unset`. The block must name a read site with a line number.
  env        the launcher leaves the name alone and dev.env states a value that is not the engine's
             documented default - a measured lever, a name the recipe's config.sh supplies, an inert
             parity name. Those are promoted into the launcher env by PROMOTION-RULES.md, so the
             proof is delivery: the recipe launcher's own forwarding filter must carry NAME=value
             into the container, or the env of record claims a setting the engine never sees.

A name whose stated value is a switch (0 or 1) is a GATED name. For every gated name the gate also
proves the filter carries the explicit off arm, the literal NAME=0: an arm a caller can set but the
filter drops is not an arm. The launcher's own gate variables (its `"$VAR" = 1` conditionals) are
proven separately: each must take the variable from the environment in `${VAR:-default}` form, so a
caller's 0 survives, and each must have its `= 1` branch, so 0 turns it off.

The filter is READ from the record, never written here: it is the line the deployed recipe launcher
uses, recorded verbatim alongside our widening patch at
upstream/recipe-launcher-tf-env/0001-launcher-forward-tf-env.patch. A copy of the same filter that
a repo script applies is checked beside it - check-prod-env.py's `--prefix` - and a copy that is
narrower than the deployed line is printed as a NOTE, because it cannot carry the names the launcher
now forwards (the screen kit's ^(TENSORFOLD|TF_FLASHNEXT)_ is one).

What this gate does not own: whether a name is a row of the served tree (check-env-coverage.py), and
whether a row cites its evidence (check-dev-env.py). It owns launcher-versus-env agreement, the
honesty of each `default` doc, deliverability through the launcher's filter, and the off arms.

  python scripts/qwen38/zig/target/env/check-launcher-contract.py
  python scripts/qwen38/zig/target/env/check-launcher-contract.py --list
"""
import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
HERE = Path(__file__).resolve().parent
DEV_LAUNCHER = "scripts/qwen38/zig/qwen6-start.sh"
RECORDED = "upstream/recipe-launcher-tf-env/0001-launcher-forward-tf-env.patch"
PROD_GATE = "scripts/qwen38/zig/target/env/check-prod-env.py"

EXPORT = re.compile(r"^export ([A-Z0-9_]+)=(.*)$")
UNSET = re.compile(r"^unset ([A-Z0-9_]+)$")
VERDICT = re.compile(r"^#\s*([a-z-]+)\s+([A-Z0-9_]+)\s*:\s*(.*)$")
DEFAULT = re.compile(r"^#\s*default\s+(.+?):\s*(.*)$")
CITE = re.compile(r"(?:zig/src|work|docs|scripts)[A-Za-z0-9_./-]*:\d+")
ASSIGN = re.compile(r"""(?:^|\s)([A-Z][A-Z0-9_]*)=("[^"]*"|'[^']*'|\S+)""")
VAR_REF = re.compile(r"^\$([A-Z][A-Z0-9_]*)$")
DEFAULTED = re.compile(r"([A-Z][A-Z0-9_]*)=\$\{\1:-([^}]*)\}")
PLAIN = re.compile(r"^([A-Z][A-Z0-9_]*)=([A-Za-z0-9_./:-]+)$")
SWITCH = re.compile(r'"\$\{?([A-Z][A-Z0-9_]*)(?::-1)?\}?"\s*=\s*1')
SERVE = re.compile(r"^(TF_|TENSORFOLD_)")
DYNAMIC = object()


def rel(path: Path) -> str:
    try:
        return path.resolve().relative_to(REPO).as_posix()
    except ValueError:
        return path.as_posix()


def read_text(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return None


def rows_of(path: Path) -> list[dict]:
    rows, block = [], []
    for number, line in enumerate((read_text(path) or "").splitlines(), start=1):
        text = line.strip()
        if text.startswith("#"):
            block.append(text)
            continue
        export, absent = EXPORT.match(line), UNSET.match(line)
        if export or absent:
            docs = [DEFAULT.match(b) for b in block if DEFAULT.match(b)]
            doc = None
            if docs:
                doc = {"value": docs[-1].group(1).strip(), "tail": docs[-1].group(2)}
            rows.append({"name": (export or absent).group(1),
                         "value": export.group(2) if export else None,
                         "line": number, "block": list(block), "doc": doc})
            block = []
        elif text:
            block = []
    return rows


def verdicts_of(path: Path) -> dict[str, tuple[str, int]]:
    out = {}
    for number, line in enumerate((read_text(path) or "").splitlines(), start=1):
        m = VERDICT.match(line)
        if m:
            out[m.group(2)] = (m.group(1), number)
    return out


def logical_lines(text: str) -> list[tuple[int, str]]:
    out, buf, first = [], "", 0
    for number, line in enumerate(text.splitlines(), start=1):
        stripped = line.rstrip()
        if stripped.endswith("\\"):
            buf += stripped[:-1] + " "
            first = first or number
            continue
        out.append((first or number, buf + stripped))
        buf, first = "", 0
    if buf:
        out.append((first, buf))
    return out


def launcher_of(path: Path) -> dict:
    text = read_text(path) or ""
    lines = logical_lines(text)
    defaults = {}
    for _, line in lines:
        for m in DEFAULTED.finditer(line):
            defaults[m.group(1)] = m.group(2)
        plain = PLAIN.match(line.strip())
        if plain:
            defaults.setdefault(plain.group(1), plain.group(2))
    block, inside = [], False
    for _, line in lines:
        stripped = line.strip()
        if not inside and stripped.startswith("exec env"):
            inside = True
        if not inside:
            continue
        if "./start.sh" in stripped:
            block.append(stripped.split("./start.sh")[0])
            break
        block.append(stripped)
    forwarded = {}
    for m in ASSIGN.finditer(" ".join(block)):
        raw = m.group(2)
        if raw[:1] in "\"'" and raw[-1:] == raw[:1]:
            raw = raw[1:-1]
        ref = VAR_REF.match(raw)
        forwarded[m.group(1)] = defaults.get(ref.group(1), DYNAMIC) if ref else raw
    gates = sorted({m.group(1) for m in SWITCH.finditer(text)})
    return {"path": path, "text": text, "defaults": defaults, "forwarded": forwarded,
            "gates": gates, "complete": bool(block) and "./start.sh" in text.split("exec env", 1)[1]}


def filter_line(path: Path) -> tuple[str, int] | None:
    lines = (read_text(path) or "").splitlines()
    patch = any(line.startswith(("+", "-")) for line in lines)
    found = []
    for number, line in enumerate(lines, start=1):
        if patch and not line.startswith("+"):
            continue
        for m in re.finditer(r"grep -E '([^']+)'", line):
            found.append((m.group(1), number))
    return found[0] if len(found) == 1 else None


def applied_prefix(path: Path) -> str | None:
    """The filter a repo script applies: check-prod-env.py names it in its --prefix default."""
    text = read_text(path)
    if text is None:
        return None
    m = re.search(r'--prefix",\s*default="([^"]*)"', text)
    return m.group(1) if m else None


def doc_matches(doc: dict, value: str | None) -> bool:
    text = doc["value"]
    low = (text + " " + doc["tail"]).lower()
    if value is None:
        return "absent" in low or "absence" in low
    if value == "":
        return text.lower().startswith("blank") or "blank is the only form" in low
    return text.split()[0] == value


def main() -> int:
    ap = argparse.ArgumentParser(description="dev.env promoted rows against the dev launcher.")
    ap.add_argument("--dev-env", default=str(HERE / "dev.env"), help="the launcher env of record")
    ap.add_argument("--register", default=str(HERE / "register.env"), help="the verdict lines")
    ap.add_argument("--launcher", action="append", default=None,
                    help=f"a launcher to parse (default {DEV_LAUNCHER}); repeatable")
    ap.add_argument("--forward-from", default=str(REPO / RECORDED),
                    help=f"the recorded deployed launcher line (default {RECORDED})")
    ap.add_argument("--list", action="store_true", help="print every promoted row's state")
    args = ap.parse_args()

    dev = Path(args.dev_env)
    register = Path(args.register)
    launchers = [Path(p) for p in (args.launcher or [str(REPO / DEV_LAUNCHER)])]
    record_file = Path(args.forward_from).resolve()
    record = filter_line(record_file)
    if record is None:
        print(f"NO-FILTER {rel(record_file)}: no single grep -E line to read the forwarding filter from")
        return 2
    regex, record_line = record
    try:
        pattern = re.compile(regex)
    except re.error as error:
        print(f"BAD-FILTER {rel(record_file)}:{record_line}: {regex}: {error}")
        return 2
    for path in [dev, register, *launchers]:
        if read_text(path) is None:
            print(f"NO-INPUT {rel(path)}: not readable")
            return 2
    rows = rows_of(dev)
    if not rows:
        print(f"NO-ROWS {rel(dev)}: no export or unset line parsed")
        return 2
    verdict = verdicts_of(register)
    retired = {name for name, (kind, _) in verdict.items() if kind == "retired"}
    parsed = [launcher_of(path) for path in launchers]

    problems, notes, listing = [], [], []
    for launcher in parsed:
        if not launcher["forwarded"]:
            problems.append(f"NO-EXEC {rel(launcher['path'])}: no `exec env` block with NAME=value tokens")
        elif not launcher["complete"]:
            problems.append(f"NO-EXEC {rel(launcher['path'])}: the exec env block does not reach ./start.sh")
        elif not any(SERVE.match(name) for name in launcher["forwarded"]):
            problems.append(f"NO-FORWARD {rel(launcher['path'])}: the launcher forwards no TF_/TENSORFOLD_ name")
    states = {"launcher": 0, "engine-default": 0, "env": 0}
    gated = {}
    seen = {}
    for row in rows:
        name, value = row["name"], row["value"]
        if name in seen:
            problems.append(f"DUPLICATE {name}: dev.env lines {seen[name]} and {row['line']}")
        seen[name] = row["line"]
        if name in retired:
            problems.append(f"RETIRED-SET {name}: dev.env line {row['line']} sets a name the register "
                            f"marks retired (line {verdict[name][1]})")
        state = None
        for launcher in parsed:
            if name not in launcher["forwarded"]:
                continue
            stated = launcher["forwarded"][name]
            if stated is DYNAMIC:
                problems.append(f"DYNAMIC {name}: {launcher['path'].name} forwards it through a variable "
                                f"whose default is not a literal, so the contract cannot be read")
            elif stated != value:
                kind = verdict.get(name)
                if kind and kind[0] == "launcher":
                    notes.append(f"launcher-wins {name}: dev.env {value!r}, launcher {stated!r} "
                                 f"(register line {kind[1]}: launcher)")
                else:
                    problems.append(f"LAUNCHER-DIFF {name}: dev.env {value!r} at line {row['line']}, "
                                    f"launcher {stated!r} ({rel(launcher['path'])})")
            state = "launcher"
        if row["doc"] is not None:
            if not doc_matches(row["doc"], value):
                problems.append(f"DEFAULT-DOC {name}: dev.env {value!r} at line {row['line']}, the doc says "
                                f"\"default {row['doc']['value']}:\"")
            if not any(CITE.search(b) for b in row["block"]):
                problems.append(f"UNCITED-DEFAULT {name}: the default doc at line {row['line']} names no "
                                f"read site with a line number")
            state = state or "engine-default"
        if value is None:
            if any(name in launcher["forwarded"] for launcher in parsed):
                problems.append(f"ABSENCE-DEFEATED {name}: dev.env line {row['line']} unsets it and the "
                                f"launcher states a value")
            state = state or "env"
        else:
            carried = f"{name}={value}"
            if not pattern.search(carried):
                problems.append(f"FILTER-REJECT {name}: {carried} is not carried by {regex} "
                                f"({rel(record_file)}:{record_line}), so the engine runs its own default")
            state = state or ("engine-default" if row["doc"] else "env")
            if value in ("0", "1"):
                gated[name] = value
        states[state] += 1
        listing.append(f"{state:<14} {name}={value if value is not None else '(unset)'} (dev.env:{row['line']})")

    names = set(seen)
    launcher_only = set()
    for launcher in parsed:
        for name, stated in launcher["forwarded"].items():
            if not SERVE.match(name) or name in names:
                continue
            launcher_only.add(name)
            if stated is DYNAMIC:
                problems.append(f"DYNAMIC {name}: {launcher['path'].name} forwards it through a variable "
                                f"whose default is not a literal")
            elif not pattern.search(f"{name}={stated}"):
                problems.append(f"UNDELIVERABLE {name}: the launcher states {stated!r} and {regex} drops it")
            if stated in ("0", "1"):
                gated.setdefault(name, stated)
            kind = verdict.get(name)
            if kind is None:
                problems.append(f"UNRECORDED {name}: the launcher states it, dev.env omits it, and the "
                                f"register has no verdict for it")

    for name in sorted(gated):
        if not pattern.search(f"{name}=0"):
            problems.append(f"OFF-ARM-DROPPED {name}: {name}=0 (the explicit off arm) is not carried by {regex}")

    gate_reading = []
    for launcher in parsed:
        for name in launcher["gates"]:
            default = launcher["defaults"].get(name, "1")
            overridable = f"{name}=${{{name}:-" in launcher["text"] or f"${{{name}:-" in launcher["text"]
            if not overridable:
                problems.append(f"GATE-HARDCODED {name}: {launcher['path'].name} reads it as a 1/0 gate but "
                                f"never takes it from the environment (no ${{{name}:-...}})")
            gate_reading.append(f"{name} ({default})")

    prefix = applied_prefix(REPO / PROD_GATE)
    if prefix:
        try:
            applied = re.compile(prefix)
        except re.error:
            applied = None
        if applied is None:
            problems.append(f"BAD-PREFIX {PROD_GATE}: {prefix} does not compile")
        else:
            dropped = sorted(n for n in names if n not in retired and not applied.search(n))
            if dropped:
                problems.append(f"GATE-FILTER {PROD_GATE}: its --prefix {prefix} drops {len(dropped)} "
                                f"promoted name(s) the deployed launcher carries: {', '.join(dropped[:5])}"
                                f"{' ...' if len(dropped) > 5 else ''}")
    driver_path = REPO / "scripts/qwen38/zig/target/screen/driver.sh"
    driver = read_text(driver_path)
    screen = re.search(r"PASSES=\$\{KS_PASSES:-'([^']+)'\}", driver) if driver else None
    screen_line = next((number for number, line in enumerate((driver or "").splitlines(), start=1)
                        if "KS_PASSES" in line), 0)
    if screen:
        try:
            narrow = re.compile(screen.group(1))
        except re.error:
            narrow = None
        if narrow is not None:
            dropped = sorted(n for n in names if n not in retired and not narrow.search(n))
            if dropped:
                notes.append(f"screen kit filter {screen.group(1)} cannot carry {len(dropped)} promoted "
                             f"name(s) of dev.env the deployed launcher forwards "
                             f"({rel(driver_path)}:{screen_line}, first: {dropped[0]})")

    for line in problems:
        print(line)
    for line in notes:
        print(f"NOTE {line}")
    if launcher_only:
        kinds = {}
        for name in sorted(launcher_only):
            kind = verdict.get(name)
            if kind:
                kinds[kind[0]] = kinds.get(kind[0], 0) + 1
        summary = ", ".join(f"{count} {kind}" for kind, count in sorted(kinds.items()))
        print(f"NOTE launcher-only: {len(launcher_only)} name(s) dev.env does not state ({summary})")
    if args.list:
        for line in listing:
            print(f"LIST {line}")
    print(f"launcher-contract: {dev.name} {len(rows)} rows, {len(retired)} retired name(s) in the register, "
          f"{len(parsed)} launcher(s), {len(verdict)} register verdict(s)")
    print(f"filter {regex} ({rel(record_file)}:{record_line}, the deployed recipe launcher line), "
          f"applied prefix {prefix or 'n/a'} ({PROD_GATE})")
    print(f"states: launcher {states['launcher']}, engine-default {states['engine-default']}, "
          f"env-carried {states['env']}; gated {len(gated)} off arm(s); "
          f"launcher gates {', '.join(gate_reading) or 'none'}")
    print(f"launcher-contract: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
