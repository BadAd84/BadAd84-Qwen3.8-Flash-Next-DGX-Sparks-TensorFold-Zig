#!/bin/bash
# check-patch-packages.sh: every patch package carries its provenance and its hashes.
#
# The repo rule is that external or upstream changes arrive as patch files applied to a pristine base, never as edits
# to that base. A patch package is therefore any directory (to depth 3 under the roots below) that directly holds
# .patch files, and each one must carry
#   RECORD.md    what it is, the repository/branch/sha it came from, the base it applies to, whether we edited it
#   SHA256SUMS   one line per .patch, in sha256sum's own format
# with every .patch listed and every hash matching.
#
# Roots come from scripts/patch-packages.list (one directory per line) and default to "upstream patches". Directories
# written before this rule existed are named in scripts/patch-packages.allow; they are skipped unless --strict, so the
# debt stays visible without blocking, and each is brought up to the rule the next time it is touched.
#
# Usage: scripts/check-patch-packages.sh [--strict]
# Exit 0 clean, 1 on any finding.
set -u
cd "$(dirname "$0")/.." || exit 1
strict=0
[ "${1:-}" = "--strict" ] && strict=1

roots=()
if [ -f scripts/patch-packages.list ]; then
  while IFS= read -r line; do
    line=${line%%#*}; line=$(echo "$line" | xargs)
    [ -n "$line" ] && roots+=("$line")
  done < scripts/patch-packages.list
else
  roots=(upstream patches)
fi

allow=()
if [ -f scripts/patch-packages.allow ]; then
  while IFS= read -r line; do
    line=${line%%#*}; line=$(echo "$line" | xargs)
    [ -n "$line" ] && allow+=("$line")
  done < scripts/patch-packages.allow
fi

fail=0
bad() { echo "  FAIL: $*"; fail=1; }
skipped=0
checked=0
for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r d; do
    mapfile -t patches < <(find "$d" -maxdepth 1 -name '*.patch' | sort)
    [ ${#patches[@]} -gt 0 ] || continue
    if [ $strict -eq 0 ] && printf '%s\n' "${allow[@]+"${allow[@]}"}" | grep -qxF "$d"; then
      skipped=$((skipped + 1)); continue
    fi
    checked=$((checked + 1))
    [ -f "$d/RECORD.md" ] || bad "$d has .patch files but no RECORD.md (source, base, provenance)"
    if [ -f "$d/SHA256SUMS" ]; then
      while read -r p; do
        base=$(basename "$p")
        grep -qE "^[0-9a-f]{64}  ${base}\$" "$d/SHA256SUMS" || bad "$d/SHA256SUMS does not list $base"
      done < <(printf '%s\n' "${patches[@]}")
      ( cd "$d" && sha256sum -c --quiet SHA256SUMS ) >/dev/null 2>&1 || bad "$d/SHA256SUMS does not match the files"
    else
      bad "$d has .patch files but no SHA256SUMS"
    fi
  done < <(find "$root" -maxdepth 3 -mindepth 1 -type d | sort)
done

if [ $fail -ne 0 ]; then
  echo "check-patch-packages: FINDINGS"
  exit 1
fi
echo "check-patch-packages: CLEAN ($checked package dirs checked, $skipped grandfathered)"
