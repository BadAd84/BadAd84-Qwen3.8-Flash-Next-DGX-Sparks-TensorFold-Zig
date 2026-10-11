#!/usr/bin/env bash
# mutants.sh: a settings-only change (TF_FLASHNEXT_PREFILL_ROWS=4096 in scripts/config.sh); no patch and no code to
# mutate. Its evidence is the interleaved A/B (merge/mverify10.sh on zmerge5; zarm2.sh on zots5) and golden 6/6 on
# every boot. Nothing to run here.
echo "settings-only: no mutant"
exit 2
