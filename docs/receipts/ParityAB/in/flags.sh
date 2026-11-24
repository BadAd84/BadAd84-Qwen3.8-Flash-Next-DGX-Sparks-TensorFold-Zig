#!/usr/bin/env bash
# flags.sh IMAGE FLAGS_FILE OUTDIR [BINARY] - put every flag an arm passes through the served binary's own parser.
#
# The oracle (PROMOTION-RULES.md): --help is not the test, the parser is. Each (flag, value) pair is run with a
# deliberately incomplete command line - a model path that does not exist - so an accepted flag reaches the model
# check ("neither a directory") and a removed one is named under "unrecognized arguments". Then the whole argv in
# one call, which is the same form the recipe's own start.sh argument check runs on every boot.
set -u
IMG=${1:?image}
FLAGS=${2:?flags file}
OUT=${3:?out dir}
BIN=${4:-/opt/tensorfold/native/bin/tensorfold-native}
mkdir -p "$OUT"
ok=0; bad=0; other=0; known=0
: > "$OUT/flags.txt"
while IFS=$'\t' read -r flag value; do
  case $flag in '#'*|'') continue;; esac
  args=(serve /nonexistent/argument-check --name parity-probe "$flag")
  [ -n "$value" ] && args+=("$value")
  err=$(docker run --rm --network none --entrypoint "$BIN" "$IMG" "${args[@]}" 2>&1 >/dev/null || true)
  # Only "unrecognized arguments" says a flag is gone. Anything else - the model check, a dependency on another
  # flag ("--vision-max-images needs --vision"), a value rule - is the parser KNOWING the flag, and the message is
  # recorded beside it so the receipt shows which class it was.
  if printf '%s' "$err" | grep -q 'neither a directory'; then
    verdict=ACCEPTED; ok=$((ok + 1))
  elif printf '%s' "$err" | grep -q "unrecognized arguments:.*$flag"; then
    verdict=REJECTED; bad=$((bad + 1))
  elif printf '%s' "$err" | grep -q -e "$flag"; then
    verdict=KNOWN; ok=$((ok + 1)); known=$((known + 1))
  else
    verdict=OTHER; other=$((other + 1))
  fi
  last=$(printf '%s' "$err" | tail -1)
  printf 'FLAG %-8s %-28s %s%s\n' "$verdict" "$flag" "${value:+$value}" \
    "$( case $verdict in KNOWN|OTHER) printf ' :: %s' "$last";; esac )" | tee -a "$OUT/flags.txt"
done < "$FLAGS"
read -r -a full < <(awk -F'\t' '!/^#/ && NF {printf "%s%s ", $1, (length($2) ? " " $2 : "")}' "$FLAGS")
err=$(docker run --rm --network none --entrypoint "$BIN" "$IMG" serve /nonexistent/argument-check --name parity-probe "${full[@]}" 2>&1 >/dev/null || true)
if printf '%s' "$err" | grep -q 'neither a directory'; then full_verdict=ACCEPTED; else full_verdict=REJECTED; fi
printf 'FLAG-FULL %-8s %s tokens :: %s\n' "$full_verdict" "${#full[@]}" "$(printf '%s' "$err" | tail -1)" | tee -a "$OUT/flags.txt"
printf 'FLAG-SUMMARY accepted %d known-other %d rejected %d other %d\n' "$ok" "$known" "$bad" "$other" | tee -a "$OUT/flags.txt"
[ "$bad" = 0 ] && [ "$full_verdict" = ACCEPTED ]
