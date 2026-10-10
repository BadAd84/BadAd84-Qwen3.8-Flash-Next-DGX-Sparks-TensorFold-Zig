#!/usr/bin/env bash
# mutants.sh (spark6): patches/0015's host test and its mutants: the lane's script runs the lanes core tests on the
# COPY_SHARED port, then each mutant (the ramp ungated, the ramp off, the proposer's source blanked; anchors asserted to
# match exactly once) must fail them. The script prints PASS/killed per mutant; judged by its exit code and its lines.
exec ~/work/lanes/w2-opus/sh4mut.sh
