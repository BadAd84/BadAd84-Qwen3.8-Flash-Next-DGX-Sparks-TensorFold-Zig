"""lean_diff.py BASE TREE: lean_check.py findings of TREE that BASE lacks, matched by file, reason and line text."""
import subprocess
import sys
from pathlib import Path


def findings(root: Path) -> set[tuple[str, str, str]]:
    out = subprocess.run([sys.executable, str(root / "tools/zig/lean_check.py")], capture_output=True, text=True).stdout
    found = set()
    for row in out.splitlines():
        if row.endswith(" problems"):
            continue
        head, _, reason = row.partition(": ")
        path, _, line = head.partition(":")
        text = (root / path).read_text(errors="replace").splitlines()[int(line) - 1] if line else ""
        found.add((path, reason, text))
    return found


new = sorted(findings(Path(sys.argv[2])) - findings(Path(sys.argv[1])))
for path, reason, text in new:
    print(f"{path}: {reason}: {text.strip()[:100]}")
print(f"lean new: {len(new)}")
sys.exit(1 if new else 0)
