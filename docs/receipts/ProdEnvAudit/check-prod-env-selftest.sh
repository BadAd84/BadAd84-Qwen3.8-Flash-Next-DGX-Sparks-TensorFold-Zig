#!/usr/bin/env bash
# check-prod-env-selftest.sh: prove the production drift gate compares the carried rows and only those.
#
# The container input is the captured live environment (live-env.txt) wrapped as a docker inspect JSON
# with the pinned production image, so the gate's image guard passes without a box. Cases:
#   1 real prod.env                         -> 0 problems, rc 0
#   2 a carried row's value changed         -> DIFF, rc 1
#   3 a pinned-default row's value changed  -> informational, rc 0
#   4 a carried row removed from prod.env   -> EXTRA (the container carries it), rc 1
#   5 a carried name removed from container -> MISSING, rc 1
#   6 a pinned name present in container    -> EXTRA (the record says the launcher does not export it), rc 1
# Prints one line a case and SELFTEST-OK 6, or SELFTEST-BAD n and exit 1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE=$HERE/../../../scripts/qwen38/zig/target/env/check-prod-env.py
PROD=$HERE/../../../scripts/qwen38/zig/target/env/prod.env
REG=$HERE/../../../scripts/qwen38/zig/target/env/register.env
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0

IMG=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
python3 - "$HERE/live-env.txt" "$T/inspect.json" "$IMG" <<'PY'
import json, sys
src, dst, image = sys.argv[1], sys.argv[2], sys.argv[3]
env = [line.strip() for line in open(src, encoding="utf-8") if line.strip()]
json.dump({"Config": {"Image": image, "Env": env}}, open(dst, "w", encoding="utf-8"))
PY
python3 - "$T/inspect.json" "$T/inspect-nowindow.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding="utf-8"))
data["Config"]["Env"] = [e for e in data["Config"]["Env"] if not e.startswith("TF_FLASHNEXT_WINDOW=")]
json.dump(data, open(dst, "w", encoding="utf-8"))
PY
python3 - "$T/inspect.json" "$T/inspect-pinned.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.load(open(src, encoding="utf-8"))
data["Config"]["Env"].append("TF_FLASHNEXT_ATTN_MULTI=5")
json.dump(data, open(dst, "w", encoding="utf-8"))
PY

run() { # name prod inspect expected-rc expected-pattern
  local name=$1 prod=$2 insp=$3 want_rc=$4 pattern=$5
  python3 "$GATE" --prod "$prod" --register "$REG" --inspect "$insp" > "$T/out" 2>&1
  local rc=$?
  local hits
  hits=$(grep -c "$pattern" "$T/out" || true)
  if [ "$rc" = "$want_rc" ] && { [ -z "$pattern" ] || [ "$hits" != 0 ]; }; then
    echo "DRIFT-SELFTEST $name ok [rc $rc${pattern:+, $hits x $pattern}]"
  else
    echo "DRIFT-SELFTEST $name FAILED want rc $want_rc${pattern:+ with $pattern} got rc $rc, $(grep -m1 "$pattern" "$T/out" || tail -1 "$T/out")"
    FAIL=$((FAIL + 1))
  fi
}

cp "$PROD" "$T/p-diff.env"
sed -i -E 's/^export TF_FLASHNEXT_WINDOW=.*/export TF_FLASHNEXT_WINDOW=63/' "$T/p-diff.env"
cp "$PROD" "$T/p-pinned.env"
sed -i -E 's/^export TF_FLASHNEXT_ATTN_MULTI=.*/export TF_FLASHNEXT_ATTN_MULTI=6/' "$T/p-pinned.env"
cp "$PROD" "$T/p-missing.env"
sed -i '/^export TF_FLASHNEXT_WINDOW=/d' "$T/p-missing.env"

run real "$PROD" "$T/inspect.json" 0 ''
run carried-value-differs "$T/p-diff.env" "$T/inspect.json" 1 '^DIFF TF_FLASHNEXT_WINDOW'
run pinned-default-differs "$T/p-pinned.env" "$T/inspect.json" 0 ''
run carried-row-removed "$T/p-missing.env" "$T/inspect.json" 1 '^EXTRA TF_FLASHNEXT_WINDOW'
run carried-name-absent "$PROD" "$T/inspect-nowindow.json" 1 '^MISSING TF_FLASHNEXT_WINDOW'
run pinned-name-carried "$PROD" "$T/inspect-pinned.json" 1 '^EXTRA TF_FLASHNEXT_ATTN_MULTI'

if [ "$FAIL" = 0 ]; then
  echo "SELFTEST-OK 6"
  exit 0
fi
echo "SELFTEST-BAD $FAIL"
exit 1
