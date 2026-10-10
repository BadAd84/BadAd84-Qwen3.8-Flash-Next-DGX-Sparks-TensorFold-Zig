#!/usr/bin/env bash
# mutants.sh: patches/0013 widens the windows a stream's copies verify in; the window's rows are drafts checked row by
# row, so replies are guarded by verification. The evidence is GPU-side and was run by hand (lane w2-fable,
# ~/work/lanes/w2-fable/hold1.sh .. hold7.sh): golden 6/6 on all 34 boots, every copy/rewrite/rename/edit reply one sha
# across every arm, 28/28 decode replies identical to the stock image. The host test "a window wider than the head's
# chain prices the chain's rows only" (cuda_lanes.zig) runs in `zig build test` (~/work/zpr/ztest.sh ~/work/zpr/tf
# test). No mutant run of its own.
echo "manual: see the header" >&2
exit 2
