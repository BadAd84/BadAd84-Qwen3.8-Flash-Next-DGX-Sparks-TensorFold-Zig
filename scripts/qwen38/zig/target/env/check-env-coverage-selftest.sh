#!/usr/bin/env bash
# check-env-coverage-selftest.sh: prove the passage gate's two directions on fixtures, with no real tree.
#
# One fixture table carries a name the launcher's filter cannot carry and one it can. The gate must fail a
# stated value it cannot carry ABOVE the defaults marker (a measured lever) and BELOW it (a stated default)
# with the same PASSAGE-LOST class, and must pass the same file when the filter matches both names. Prints
# one line a case and SELFTEST-OK, or SELFTEST-BAD n and exit 1.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
GATE=$HERE/check-env-coverage.py
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
FAIL=0

proof() { # name expected actual
  if [ "$2" = "$3" ]; then
    echo "GATE-SELFTEST $1 ok [$3]"
  else
    echo "GATE-SELFTEST $1 FAILED want [$2] got [$3]"
    FAIL=$((FAIL + 1))
  fi
}

cat > "$T/table-plain.zig" <<'EOF'
        .{ .name = "TF_FLASHNEXT_A", .scope = .cuda, .forms = "bool" },
        .{ .name = "TF_PLAIN_B", .scope = .cuda, .forms = "bool" },
EOF
cat > "$T/table-ok.zig" <<'EOF'
        .{ .name = "TF_FLASHNEXT_A", .scope = .cuda, .forms = "bool" },
        .{ .name = "TF_FLASHNEXT_B", .scope = .cuda, .forms = "bool" },
EOF
printf '# measured lever\nexport TF_FLASHNEXT_A=1\n# --- explicit defaults\nexport TF_PLAIN_B=0\n' > "$T/env-below.env"
printf '# measured lever\nexport TF_PLAIN_B=1\n# --- explicit defaults\nexport TF_FLASHNEXT_A=0\n' > "$T/env-above.env"
printf '# measured lever\nexport TF_FLASHNEXT_A=1\n# --- explicit defaults\nexport TF_FLASHNEXT_B=0\n' > "$T/env-ok.env"
: > "$T/register.env"

run() { # dev passes -> exit code, output in $T/out
  python3 "$GATE" --table "$1" --dev "$2" --register "$T/register.env" --scopes cuda \
    --passes "$3" > "$T/out" 2>&1
}

run "$T/table-plain.zig" "$T/env-below.env" '^(TENSORFOLD|TF_FLASHNEXT)_'
proof below-marker-fails 1 "$?"
proof below-marker-line 1 "$(grep -c 'PASSAGE-LOST TF_PLAIN_B.*a stated default' "$T/out" || true)"

run "$T/table-plain.zig" "$T/env-above.env" '^(TENSORFOLD|TF_FLASHNEXT)_'
proof above-marker-fails 1 "$?"
proof above-marker-line 1 "$(grep -c 'PASSAGE-LOST TF_PLAIN_B.*a measured lever' "$T/out" || true)"

run "$T/table-ok.zig" "$T/env-ok.env" '^(TENSORFOLD|TF_FLASHNEXT)_'
proof carried-below-passes 0 "$?"

run "$T/table-plain.zig" "$T/env-below.env" '^TF_'
proof wider-filter-passes 0 "$?"

if [ "$FAIL" = 0 ]; then
  echo "SELFTEST-OK 4"
  exit 0
fi
echo "SELFTEST-BAD $FAIL"
exit 1
