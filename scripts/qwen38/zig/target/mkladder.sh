#!/usr/bin/env bash
# mkladder.sh OUT - the whole ladder from the old series and overlay.py's repairs: one cumulative patch a lever
# (OUT/rungs/rNNNN.patch), then the additive series (OUT/series/NNNN-<lever>.patch, replayed onto pristine to prove
# it reproduces the last rung) and the reverts gate over it. Run it sourced: ( set -- OUT; . mkladder.sh )
OUT=${1:?output dir}
REPO=/c/Users/Adam/Gitea/Qwen3.8-Flash-Next-DGX-Sparks-TensorFold-Zig
T=/c/Users/Adam/Gitea/tf-lc
mkdir -p "$OUT/rungs" "$OUT/series"
LADDER="0005:rows 0006:copy-resync 0012:kv8 0015:ngram-row-cache 0017:prompt-chunk 0019:prompt-gemm2 0021:draft-head-4bit 0025:prompt-readout-fused 0026:readout-q12 0027:round-cost 0029:vision 0031:gather-direct 0032:check-log"
specs=""
for item in $LADDER; do
  K=${item%%:*}; name=${item#*:}
  line=$( ( set -- "$K"; . "$REPO/scripts/qwen38/zig/target/mkrung.sh" ) 2>&1 | tail -1 ); echo "$line"
  case "$line" in "rung $K: "*" old patches, "*) ;; *) echo "mkladder: rung $K did not build: stop"; return 2 2>/dev/null || exit 2 ;; esac
  ( cd "$T" && git ls-files --others --exclude-standard -z | xargs -0 -r git add -N -- && git diff --binary > "$(cygpath -m "$OUT/rungs/r$K.patch")" && git reset -q )
  specs="$specs $name:$OUT/rungs/r$K.patch"
done
# shellcheck disable=SC2086
( set -- "$OUT/series" $specs; . "$REPO/scripts/qwen38/zig/target/mkseries.sh" )
python "$(cygpath -m "$REPO/scripts/check-patch-reverts.py")" "$(cygpath -m "$OUT/series")" | tail -40
