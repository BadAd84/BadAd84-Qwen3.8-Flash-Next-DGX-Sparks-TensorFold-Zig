# r5dev40: the single dev composition built, booted and proved on spark6

Image `tensorfold-qwen38:r5dev40`, id `sha256:adc40fe3ea7b58b78f7957fcf37dbf3ac7e8d635172ccc42b4c5c85efeded74f`,
from a pristine TensorFold `1ece6e6d` plus the 40 patches of `patches/main-1ece6e6db-r5-dev/` applied in order
(manifest `dd655181afd5494ea78711c96f2240a5bf1d787cbcea207c17f971f2c6d31d19`, 12,635 files). Build 459 s. Evidence:
`ev.tgz` beside this file (118 files: run log, exactness, boot and plan lines, turn2, the contract window and the first
failed build attempt).

After this boot the package gained a comment-only pass (commit `a68f2d9d`, manifest
`9e3c2276cbf297d71e3d5b072f801ae18b2309f8b213e9754b8cac3aa1c359e4`): 94 comment lines condensed and five pin rows
regenerated from the same fixture bytes, no engine line changed. The image above stays the dev arm of record; the next
rebuild regenerates from the current package.

## Boot

Through `~/qwen6-start.sh` (the repo copy, `cce62b64...`) with `dev.env` sourced, `LOCK_HOLDER=0 PARALLEL=8
CONTEXT=262144 WARM_TURNS=0`, image `r5dev40`. Banner: `INT4-AutoRound · 8 at once · 262144-token window · fp8 KV ·
vision off · drafts MTP · port 8888`. Server answered after 166 s. Plan: model 75.85 GiB, 7 more streams taking 220
pages of 4096 rows (15.84 GiB), `a 6.0 GiB prompt cache`.

The container carried the promoted values: `TENSORFOLD_CUDA_KERNELS=native`, `KV_PAGES=4096`,
`MTP_WEIGHTS=mxfp8`, `SHARED_DRAFTS=0`, `HEAD_ROW_TILES=2`, `INT4_PROMPT_GATE_UP=1`, `INT4_PROMPT_DOWN=1`,
`INT4_TILE=16`; cmd `--kv-cache fp8 --prompt-cache-gib 6 --learn-gib 60 --learn-daily-gib 200
--learn-min-free-gib 20`.

## Proofs

- Window self-check: `1176 of 1176 rows byte-equal to their one-token steps (widths 1-48)`.
- Exactness: 5 cells EQ, `drafted_total 404`, `sha_matches_ids True`: p200 and p2k drafted-vs-plain (109 and 92 drafts
  against 0 on the plain side), concurrent-vs-solo with 3 of 3 background streams decoding (each 2400 ids in 39.2 s),
  and resume resumed-vs-fresh and repeats at 24 ids with cached 2417.
- int4 contract on the composition (`zig build int4-contract`, box Zig mounted, nvcc 13.3, rc 0, 170/170 steps):
  `SUMMARY int4: 8 kernels, 8 pass gates 1-4, 0 fail, 0 known findings; 5 controls: 5 red as planted, 0 missed`.
  The three gate/up controls of the tolerance port are among the five, and the skipped-slot check passes.
- KV tier: the launcher's `--prompt-cache-gib 6` is 6,442,450,944 B and the store reports `of 6144 MiB`, so the
  full-ask patch makes budget and ask equal (the old image gave half). A 129k conversation: cold 52.487 s, resume
  0.176 s with the same sha, appended turn 0.372 s, and the base conversation re-asked at 0.154 s with the same sha
  (`TURN2-SURVIVAL A3_cached 129000 survived True`), so both states live under the 6 GiB budget. Disk imprint writes
  129,000 tokens in 492 ms; the resume is served from RAM.

## Gaps stated

- `/stats` returns 404 on this boot: the dev launcher passes only the tier args to `start.sh restart` and has no
  `--dashboard` pass-through (`status_routes.zig:255` gates it). The budget was read from the plan and the store's own
  lines instead.
- One build defect cost a window: BuildKit served a cached fetch layer keyed to the command string with
  `refs/heads/main`, so the build started from another lane's base. The working build served a unique ref
  (`refs/heads/r5dev40-1795489890`) and forced the 719 tracked-but-gitignored receipts into the served tree by
  naming them explicitly.
  Recorded in the README build section.

## Restore

`PROD-IMAGE-OK` on `zmerge8-kfix-e5139fcd8c6101c7` id `235211ea`, `/health` 200, and the drift check EQUAL three times
(before cleanup, after the contract hold, after cleanup): `54 settings, 54 equal, 0 problem(s)`.
