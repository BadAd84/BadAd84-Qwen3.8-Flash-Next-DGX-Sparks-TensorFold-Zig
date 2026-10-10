#!/usr/bin/env bash
# mutants.sh (spark6): patches/0012's host tests and their mutants: the lane's script applies each mutant of
# cuda_ngram_host.zig exactly once (asserted), runs `zig build test`, restores the file (md5 asserted). Mutants: a block
# skipping its last row, a draft predecessor off by one, the gang's error swallowed, a block written at the wrong
# offset; each must fail the tests. Exactness on the GPU: golden 6/6 and every reply sha equal across arms (holds
# m1/m2, w1_measure1.sh / w1_measure2.sh). The lane's script prints each run's summary line: read it, a mutant whose
# summary says "passed" survived.
exec ~/work/lanes/w1-fable/mutants.sh
