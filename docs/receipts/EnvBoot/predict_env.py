"""Which of the dev env's unstated rows the dev launcher (config.sh + qwen6-start.sh) sets anyway.

Runs on the box. Reads the settings expectation (in/env-table-rows.txt), the recipe's config.sh and the dev
launcher's `exec env` block, and prints one line per unstated row: the name, and either the value the
launcher sets or LAUNCHER-DOES-NOT-SET.
"""
import re

ROWS = "/home/adam/work/EnvBoot/in/env-table-rows.txt"
CFG = "/home/adam/qwen-zig/scripts/config.sh"
LAU = "/home/adam/qwen6-start.sh"

cfg = {}
for line in open(CFG, encoding="utf-8"):
    m = re.search(r'export ([A-Z0-9_]+)="\$\{\1:-([^}]*)\}"', line)
    if m:
        cfg[m.group(1)] = m.group(2)
    else:
        m = re.search(r'^export ([A-Z0-9_]+)="?([^"\n]*)"?$', line)
        if m:
            cfg[m.group(1)] = m.group(2)

lau = {}
in_env = False
for line in open(LAU, encoding="utf-8"):
    if re.search(r"^\s*exec env \\$", line) or re.search(r"^\s*exec env\b", line):
        in_env = True
        continue
    if in_env:
        if "./start.sh restart" in line:
            break
        for m in re.finditer(r"([A-Z][A-Z0-9_]*)=\"?([^\"\s]*)", line):
            lau.setdefault(m.group(1), m.group(2))

rows = [l.rstrip("\n").split("\t") for l in open(ROWS, encoding="utf-8") if l.strip()]
missing = [(r[0], r[1]) for r in rows if r[2] == "missing"]
print(f"unstated rows {len(missing)}; config.sh exports {len(cfg)}; launcher env {len(lau)}")
for name, scope in missing:
    if name in lau:
        print(f"LAUNCHER\t{name}={lau[name]}\t{scope}")
    elif name in cfg:
        print(f"CONFIG\t{name}={cfg[name]}\t{scope}")
    else:
        print(f"UNSET\t{name}\t{scope}\tengine default applies")
print("-- launcher/config names that are not table rows --")
names = set(cfg) | set(lau)
tab = {r[0] for r in rows}
print(" ".join(sorted(n for n in names if n not in tab and n.startswith(("TF_", "TENSORFOLD_")))))
