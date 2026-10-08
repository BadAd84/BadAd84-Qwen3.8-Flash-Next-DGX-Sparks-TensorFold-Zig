#!/usr/bin/env bash
# mutants.sh: a configuration default only (TF_FLASHNEXT_CONFIDENCE). No code to mutate: the evidence is the HTTP A/B
# (scripts/qwen38/zig/zqueue.sh, arms stock / c015) with golden replies byte-identical in every boot.
echo "no mutants: a setting, not code" >&2
exit 0
