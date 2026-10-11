#!/usr/bin/env bash
# mutants.sh (spark6): patches/0015's host test and its mutants: the lane's script runs the lanes core tests on the
# COPY_SHARED port, then each mutant (the ramp ungated, the ramp off, the proposer's source blanked; anchors asserted to
# match exactly once) must fail them. The script prints PASS/killed per mutant; judged by its exit code and its lines.
# Review round 1 (2026-10-11), on the fixed stack (~/work/lanes/r1-fix, tf branch `stack`): the round's
# new host tests and a mutant each, judged by exit code (hostmut.py exits 0 only when every one is killed).
python3 ~/work/lanes/r1-fix/hostmut.py last-out-not-cleared || exit 1
exec ~/work/lanes/w2-opus/sh4mut.sh
