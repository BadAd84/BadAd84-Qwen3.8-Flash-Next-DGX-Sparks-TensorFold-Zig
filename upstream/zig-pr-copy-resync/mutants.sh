#!/usr/bin/env bash
# mutants.sh: patches/0014 is drafting policy (which tokens are proposed as copies, how many); replies are guarded by
# verification. Evidence: golden 6/6 and one sha per copy case across every arm (lane w2-fable holds hold4-hold7,
# ~/work/lanes/w2-fable/hold*.sh), the prompt-only gate's round counts equal to the control's, and the proposer's host
# tests in core/lanes/proposer.zig (`zig build test`: ~/work/zpr/ztest.sh ~/work/zpr/tf test). No mutant run of its own.
echo "manual: see the header" >&2
exit 2
