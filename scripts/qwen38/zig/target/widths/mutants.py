#!/usr/bin/env python3
"""mutants.py NAME DIR - apply the named mutant of the widths change to the tree DIR in place; each anchor must match
exactly once."""
import sys
from pathlib import Path

F = "zig/src/families/flashnext"
MUTANTS = {
    "default-only": (f"{F}/cuda_widths.zig",
                     "pub const supported = [_]Widths{ default, .{ .top_k = 5, .shared = 2 * wt.moe_w } };",
                     "pub const supported = [_]Widths{default};"),
    "mlx-any": (f"{F}/cuda_config.zig",
                'return if (widthsOf(text).widths.isDefault()) null else "num_experts_per_tok";',
                "return null;"),
    "scratch-const": (f"{F}/cuda_batch_state.zig",
                      "n += cap * z.shared * 6 + cap * dims * 4;",
                      "n += cap * moe_w * 6 + cap * dims * 4;"),
    "mtp-any": (f"{F}/cuda_widths.zig",
                "if (shared_rows != main.shared and shared_rows != wt.moe_w) return null;",
                "if (false) return null;"),
    "captured-any": (f"{F}/cuda_widths.zig", "    return w.isDefault();\n}", "    _ = w;\n    return true;\n}"),
    "fixed-top10": (f"{F}/cuda_widths.zig",
                    "if (top_k != @as(i64, @intCast(w.top_k))) continue;",
                    "if (top_k != 10) continue;"),
}

name, root = sys.argv[1], Path(sys.argv[2])
path, old, new = MUTANTS[name]
p = root / path
s = p.read_text()
assert s.count(old) == 1, (name, s.count(old))
p.write_text(s.replace(old, new))
print(f"applied {name} to {path}")
