#!/usr/bin/env bash
# gated.sh - the widths receipt and its exactness arms, queued behind Fp4Confirm's chain (its windows run back to back).
until grep -q "chain done" ~/work/fp4stack/chain.out 2>/dev/null; do sleep 60; done
rm -f ~/work/widths/receipt/DONE
bash ~/work/widths/receiptW.sh 2ba55ec7d32d0bec446bb012678550be7ef52895 "$HOME/work/widths/0001-flashnext-config-widths.patch"
bash ~/work/widths/exactW.sh
