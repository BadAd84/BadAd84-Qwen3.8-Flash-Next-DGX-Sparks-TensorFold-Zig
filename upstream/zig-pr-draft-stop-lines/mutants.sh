#!/usr/bin/env bash
# mutants.sh (spark6): patches/0020's split stop lines (cuda_decode.Stop.tp / tc). The script runs `zig build test` on
# the clean stack (~/work/zpr/tf = 0001-0020; no GPU), then two mutants of Stop.take in scratch copies (anchors asserted
# to match once): the propose test made against the continue line, the continue test made always true. Exit 0 only
# when the unmutated tree passes and both mutants fail. Last run 2026-10-10: unmutated pass; both killed; exit 0. The
# int4 draft head and the depth cap are guarded by the target's verification (golden 6/6 on 33 lane boots).
# Review round 1 (2026-10-11), on the fixed stack (~/work/lanes/r1-fix, tf branch `stack`): the round's
# new host tests and a mutant each, judged by exit code (hostmut.py exits 0 only when every one is killed).
python3 ~/work/lanes/r1-fix/hostmut.py draft-lines-one-silently-ignored draft-ids-pad-without-int4 || exit 1
exec ~/work/zpr/mut0020.sh
