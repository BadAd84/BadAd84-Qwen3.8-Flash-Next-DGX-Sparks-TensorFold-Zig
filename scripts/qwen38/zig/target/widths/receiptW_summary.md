# Widths receipt (#3368 step 1): main 2ba55ec7d3 (image wm) against main plus the widths patch (wb, patch sha256 prefix 72b26f3ce07dc3e9), spark6, 2026-11-15

START 2026-11-15T02:12:55+00:00 base 2ba55ec7d32d0bec446bb012678550be7ef52895 patch 72b26f3ce07dc3e9
BUILD wb rc 0 
IMAGE wm e971c21a08f5
IMAGE wb 2753b07e7e0c
=== M1 2026-11-15T02:20:51+00:00 boot rc 0 gpu 44,2431MHz
=== B1 2026-11-15T02:24:03+00:00 boot rc 0 gpu 52,2470MHz
=== B2 2026-11-15T02:27:14+00:00 boot rc 0 gpu 55,2405MHz
=== M2 2026-11-15T02:30:25+00:00 boot rc 0 gpu 56,2418MHz
ARMS DONE 2026-11-15T02:33:02+00:00
RESTORE prod /health 200 2026-11-15T02:34:30+00:00

## bench_concurrent --alone --serial, greedy, 256 tokens, 3 reps: per-stream decode tok/s
| prompt | streams | M1 | B1 | B2 | M2 | branch/main | verdict | alone equal (M1 B1 B2 M2) |
|---|---|---|---|---|---|---|---|---|
| code | 1 | 72.6 | 72.7 | 72.4 | 72.7 | -0.14% | no slower | 3/3 3/3 3/3 3/3 |
| code | 2 | 69.7 | 69.7 | 69.8 | 69.8 | +0.00% | no slower | 6/6 6/6 6/6 6/6 |
| code | 4 | 62.5 | 62.3 | 62.3 | 62.2 | -0.08% | no slower | 12/12 12/12 12/12 12/12 |
| chat | 1 | 46.7 | 46.6 | 46.6 | 46.5 | +0.00% | no slower | 3/3 3/3 3/3 3/3 |
| chat | 2 | 43.6 | 43.6 | 43.5 | 43.5 | +0.00% | no slower | 6/6 6/6 6/6 6/6 |
| chat | 4 | 39.8 | 39.6 | 39.5 | 39.5 | -0.25% | no slower | 12/12 12/12 12/12 12/12 |

## bench_openai, greedy, 256 tokens: median decode tok/s of 3
| prompt | M1 | B1 | B2 | M2 | branch/main | verdict |
|---|---|---|---|---|---|---|
| fibonacci-raw | 72.44 | 72.45 | 72.36 | 72.22 | +0.10% | no slower |
| gpu-chat-no-think | 46.68 | 46.53 | 46.48 | 46.49 | -0.18% | no slower |

## Accepted per round over each bench (mtp_accepted_total / decode_rounds_total)
- M1: conc_t0 2.073 (7934 of 11682 drafted, 3827 rounds); openai_t0 2.696 (1488 of 2384 drafted, 552 rounds)
- B1: conc_t0 2.073 (7934 of 11682 drafted, 3827 rounds); openai_t0 2.696 (1488 of 2384 drafted, 552 rounds)
- B2: conc_t0 2.073 (7934 of 11682 drafted, 3827 rounds); openai_t0 2.696 (1488 of 2384 drafted, 552 rounds)
- M2: conc_t0 2.073 (7934 of 11682 drafted, 3827 rounds); openai_t0 2.696 (1488 of 2384 drafted, 552 rounds)

## Resident memory after boot (docker stats)
M1 4.07GiB B1 4.067GiB B2 4.066GiB M2 4.046GiB

## Token hashes against M1's (bench_concurrent alone and serial, widest cell, first rep)
- M1: 8/8 equal to M1; alone 42/42 equal, serial 2/2 equal, 0 failed, [256] tokens
- B1: 8/8 equal to M1; alone 42/42 equal, serial 2/2 equal, 0 failed, [256] tokens
- B2: 8/8 equal to M1; alone 42/42 equal, serial 2/2 equal, 0 failed, [256] tokens
- M2: 8/8 equal to M1; alone 42/42 equal, serial 2/2 equal, 0 failed, [256] tokens
