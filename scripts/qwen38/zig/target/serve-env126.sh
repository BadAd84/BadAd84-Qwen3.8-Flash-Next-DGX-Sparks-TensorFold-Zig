#!/usr/bin/env bash
# serve-env126.sh - the v1.2.6 stack's measured serve environment (2026-11-11), for any launch through the campaign
# recipe: `env $(serve-env126.sh) IMAGE=... ./start.sh restart`. Every knob here was measured at the target settings
# (nvfp4, fp8 KV, 262,144 tokens) at C=1 and C=4, against a warm baseline, replies 6/6 identical.
#
# GATHER_READ=0: the n-gram pread row cache with O_DIRECT is 2 to 7% SLOWER than the plain reader (confirmed A/B/A);
# the buffered variant (TF_FLASHNEXT_GATHER_DIRECT=0, patch 0031) only ties it, so the plain reader is the default.
# ATTN_LANES=1, DECODE_GRAPH=1 (needs SPLIT_DENSE=0) and CHUNK=1024 are each worth 0 to 2% alone and 3.1% stacked at
# both stream counts; measured as one arm, twice, in an ABBA against its own baseline.
# Do not set TF_FLASHNEXT_WINDOW_ROWS: 32 costs 5% at four streams.
printf '%s' 'TF_FLASHNEXT_GATHER_READ=0 TF_FLASHNEXT_ATTN_LANES=1 TF_FLASHNEXT_DECODE_GRAPH=1 TF_FLASHNEXT_SPLIT_DENSE=0 TF_FLASHNEXT_CHUNK=1024'
