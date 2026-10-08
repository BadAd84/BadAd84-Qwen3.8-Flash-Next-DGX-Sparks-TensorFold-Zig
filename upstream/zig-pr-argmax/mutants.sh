#!/usr/bin/env bash
# mutants.sh (spark6): patches/0010's bit-exactness check and its mutants: check_rows.cu runs the patched argmax and
# logsumexp-max launches against the shipped ones on 120 adversarial rows (ties, NaN, +-inf, +-0, tail maxima, widths
# 1 to 248,320), then three mutants of the new loop must each make it fail. Judged by exit code.
# Last run 2026-10-08 23:5x: PASS, 120 rows, 0 differences; mutants no-tail, unroll3, bound: killed.
exec ~/work/check0010/run.sh "${1:-$HOME/work/zsrc/tf}"
