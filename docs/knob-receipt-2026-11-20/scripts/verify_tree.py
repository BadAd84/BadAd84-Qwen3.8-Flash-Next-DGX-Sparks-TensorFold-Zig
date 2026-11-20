"""verify_tree.py MANIFEST.json TREE_DIR - check an extracted tree blob by blob.

For every recorded blob: the file must exist, its bytes must hash to the recorded git blob object name
(sha1 of "blob <len>\\0" + bytes), its executable bit must match the recorded mode, and no extra file may be
present. Submodule entries must be present as directories. Exit 1 on any mismatch; prints a summary line.
"""
import hashlib
import json
import os
import sys

manifest_path, tree = sys.argv[1], sys.argv[2]
man = json.load(open(manifest_path, encoding="utf-8"))
bad = []
seen = set()
for e in man["entries"]:
    p = os.path.join(tree, e["path"])
    seen.add(os.path.abspath(p))
    if e["kind"] == "commit":
        if not os.path.isdir(p):
            bad.append(f"missing submodule dir {e['path']}")
        continue
    if not os.path.isfile(p):
        bad.append(f"missing {e['path']}")
        continue
    n = os.stat(p).st_size
    h = hashlib.sha1(b"blob %d\0" % n)
    with open(p, "rb") as f:
        while True:
            chunk = f.read(1 << 20)
            if not chunk:
                break
            h.update(chunk)
    got = h.hexdigest()
    if got != e["object"]:
        bad.append(f"blob mismatch {e['path']} want {e['object']} got {got}")
    want_exec = e["mode"] == "100755"
    got_exec = bool(os.stat(p).st_mode & 0o100)
    if want_exec != got_exec:
        bad.append(f"mode mismatch {e['path']} want {e['mode']} exec {got_exec}")
extra = []
for root, dirs, files in os.walk(tree):
    for name in files:
        fp = os.path.abspath(os.path.join(root, name))
        if fp not in seen:
            extra.append(os.path.relpath(fp, tree))
print(f"TREE {tree} manifest_sha {man['sha']} entries {len(man['entries'])} "
      f"mismatches {len(bad)} extra_files {len(extra)}")
for b in bad[:20]:
    print("BAD", b)
for x in extra[:20]:
    print("EXTRA", x)
sys.exit(1 if bad or extra else 0)
