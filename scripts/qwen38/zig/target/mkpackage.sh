#!/usr/bin/env bash
# mkpackage.sh SERIES_DIR PKG_DIR - a patch package from an additive series (mkladder.sh's OUT/series): the numbered
# patches, SHA256SUMS in sha256sum's format, and apply.sh. RECORD.md and README.md are written by hand; the gate
# (scripts/check-patch-packages.sh) wants RECORD.md beside them. BASE is the sha apply.sh insists on (default
# v1.2.6, 6e9af930). Run it sourced: ( set -- SERIES PKG; . mkpackage.sh )
SERIES=${1:?series dir}; PKG=${2:?package dir}
BASE=${BASE:-6e9af930261a88bb28ac0bfb157ce8e57e9eea07}
mkdir -p "$PKG"
rm -f "$PKG"/[0-9]*.patch
cp "$SERIES"/[0-9]*.patch "$PKG"/
python - "$(cygpath -m "$PKG")" "$BASE" <<'PY'
import glob, hashlib, io, os, re, sys
pkg, base = sys.argv[1], sys.argv[2]
assert re.fullmatch(r"[0-9a-f]{40}", base), "BASE must be a full sha"
lines = []
for p in sorted(glob.glob(os.path.join(pkg, "[0-9]*.patch"))):
    lines.append(f"{hashlib.sha256(open(p, 'rb').read()).hexdigest()}  {os.path.basename(p)}\n")
io.open(os.path.join(pkg, "SHA256SUMS"), "w", newline="\n").write("".join(lines))
apply = r'''#!/usr/bin/env bash
# apply.sh [--check] TREE - the series onto a pristine TensorFold checkout at the base below, in filename order.
# --check proves the whole series applies and writes nothing to TREE's files or index: it uses a scratch index.
set -euo pipefail
BASE=@BASE@
check=0
if [ "${1:-}" = "--check" ]; then check=1; shift; fi
TREE=${1:?usage: apply.sh [--check] TREE}
HERE=$(cd "$(dirname "$0")" && pwd)
( cd "$HERE" && sha256sum -c --quiet SHA256SUMS ) || { echo "apply.sh: the patches do not match SHA256SUMS"; exit 2; }
cd "$TREE"
[ "$(git rev-parse HEAD)" = "$BASE" ] || { echo "apply.sh: $TREE is not at $BASE"; exit 2; }
n=0
if [ "$check" = 1 ]; then
  idx="$(git rev-parse --git-dir)/apply-check.index"
  rm -f "$idx"
  trap 'rm -f "$idx"' EXIT
  export GIT_INDEX_FILE="$idx"
  git read-tree HEAD
  for p in "$HERE"/[0-9]*.patch; do
    git apply --cached --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
    n=$((n + 1))
  done
  echo "apply.sh: $n patches apply on $BASE in order (nothing written)"
  exit 0
fi
[ -z "$(git status --porcelain)" ] || { echo "apply.sh: $TREE has local changes"; exit 2; }
for p in "$HERE"/[0-9]*.patch; do
  git apply --whitespace=nowarn "$p" || { echo "apply.sh: $(basename "$p") does not apply"; exit 1; }
  n=$((n + 1))
done
echo "apply.sh: $n patches applied on $BASE"
'''.replace("@BASE@", base)
io.open(os.path.join(pkg, "apply.sh"), "w", newline="\n").write(apply)
print(f"package: {len(lines)} patches, SHA256SUMS, apply.sh on {base[:10]} in {pkg}")
PY
