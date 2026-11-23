"""mutants.py TREE guard|window - the two faithful mutants of the draft-head fix.

`guard`: the two named refusals removed (the pre-fix behaviour of Head.project and Head.init, the rest of the fix
kept), so the new host test must fail with qlinear's own error.FormatMismatch.

`window`: the drafter's recode window restored to the function scope the series had (its `{` and `}` removed, so the
`defer` sits at the function's own scope), so the head loads under TF_FLASHNEXT_MTP_WEIGHTS again; the refusals still
stand, so on host the tests pass (Head.init needs a CUDA device and the test builds its own Head), and the device
window is this mutant's test.

Every anchor must match exactly once; a drifted anchor is a finding, never a silent no-op.
"""
import io
import os
import sys

GUARD = (
    "\n        if (!storedRows(&h.draft)) return error.DraftHeadFormat;",
    "\n            if (!storedRows(&h.draft)) return error.DraftHeadFormat;",
)

WINDOW = (
    ("        // the drafter's own linears only: the window closes before the draft head's own rows are read\n        {\n",
     "        // the drafter's own linears only: the window closes before the draft head's own rows are read\n"),
    ("        }\n        store.dropStaging(); // the head's experts are on the device\n",
     "        store.dropStaging(); // the head's experts are on the device\n"),
)


def main():
    tree, mode = sys.argv[1], sys.argv[2]
    path = os.path.join(tree, "zig/src/families/flashnext/cuda_mtp.zig")
    text = io.open(path, encoding="utf-8", newline="").read()
    if mode == "guard":
        pairs = [(anchor, "") for anchor in GUARD]
    elif mode == "window":
        pairs = list(WINDOW)
    else:
        raise SystemExit(f"mutate: unknown mode {mode}")
    for old, new in pairs:
        n = text.count(old)
        if n != 1:
            raise SystemExit(f"mutate: {mode} anchor matched {n} times, expected exactly 1: {old.strip().splitlines()[0][:70]}")
        text = text.replace(old, new)
    io.open(path, "w", encoding="utf-8", newline="").write(text)
    print(f"mutate: {mode} applied to {path} ({len(pairs)} anchors)")


if __name__ == "__main__":
    main()
