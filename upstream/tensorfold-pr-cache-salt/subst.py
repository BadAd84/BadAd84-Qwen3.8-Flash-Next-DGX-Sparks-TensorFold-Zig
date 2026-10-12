"""subst.py FILE OLD NEW: replace OLD with NEW in FILE once; fails unless OLD occurs exactly once (\\n escapes)."""
import sys

path, old, new = sys.argv[1], sys.argv[2].replace("\\n", "\n"), sys.argv[3].replace("\\n", "\n")
text = open(path).read()
count = text.count(old)
if count != 1:
    sys.exit(f"anchor matched {count} times in {path}")
open(path, "w").write(text.replace(old, new, 1))
