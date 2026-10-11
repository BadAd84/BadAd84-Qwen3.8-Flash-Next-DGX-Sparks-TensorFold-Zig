#!/usr/bin/env bash
# mutants.sh: patches/0013 widens the windows a stream's copies verify in; the window's rows are drafts checked row by
# row, so replies are guarded by verification. The evidence is GPU-side and was run by hand (lane w2-fable,
# ~/work/lanes/w2-fable/hold1.sh .. hold7.sh): golden 6/6 on all 34 boots, every copy/rewrite/rename/edit reply one sha
# across every arm, 28/28 decode replies identical to the stock image. The host test "a window wider than the head's
# chain prices the chain's rows only" (cuda_lanes.zig) runs in `zig build test` (~/work/zpr/ztest.sh ~/work/zpr/tf
# test). No mutant run of its own.
# Review round 1 (2026-10-11), on the fixed stack image tensorfold-qwen38:zpr-r1-stack:
# `window-check` passes on the fixed stack and fails with each mutant binary (gmutants.json):
bash ~/work/lanes/r1-fix/gpucheck.sh window-check fp8-rows-past-16-half-slices || exit 1
echo "manual: see the header" >&2
exit 2
