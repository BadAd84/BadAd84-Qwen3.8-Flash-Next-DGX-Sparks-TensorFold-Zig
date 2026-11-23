# Step 5's admission half, measured on the int4s5 image with bf16 KV

The step-5 tree keeps bf16 caches and refuses `--kv-cache fp8` by name, so the earlier attempts died before serving.
The driver was fixed to honour `KV_DTYPE` and `BOOT_CONTEXT` (it had hardcoded fp8 and 262144), and the window ran on
2026-11-23 after the GPU lock's self-deadlock cleared. Receipts: `out-fetched/` (fetched from
`~/work/Int4Step5Dev/out`); this file is their summary.

## What booted

- Image `tensorfold-qwen38:int4s5`, `sha256:eec50f2725a7b35321fb30dfd8dd47ac60929adc2d783dd72c02a66b368b3b71`, cache `embedded`.
- Banner: `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 131072-token window · bf16 KV · vision off · drafts off · port 8080`.
- Plan line: `model 71.92 GiB; 8 streams at once, the engine's own at a 131072-token window (3.58 GiB, in the model's), 7 more taking 238 pages of 4096 rows (25.80 GiB) as they need them, 0 MiB fixed each, of 32.3 GiB left after a 10.0 GiB reserve; prompts in passes of up to 16384 rows, a 1.6 GiB prompt cache`.
- `start.sh` checked `114 GiB memory available (this window needs ~90 at start)`; the boot returned `rc 0`, `/health` 200,
  `BOOT admitted boot-served8 health 200` at 21:05:44.

The two refusal controls behaved as planted before it: `boot-refuse-drafts` and `boot-refuse-tp2` each exited rc 1 with
no serve, which is their expected result.

## The int4 contract inside the served boot

`SUMMARY int4: 8 kernels, 8 pass gates 1-4, 0 fail, 0 known findings; 2 controls: 2 red as planted, 0 missed`, with the
fidelity and allowance tables in `summary.txt` (e.g. `FID head rows=512 n=248320 k=2560`, `ALLOW head ... max=1.730e-2`).
This is the same suite the device receipt ran on the FP4 arm, reproduced at this image and shape.

## Exactness cells

`EXACTNESS PASS cells 5 drafted_total 0 sha_matches_ids True draft_true_error -`

| cell | verdict | sha16 | ids |
|---|---|---|---|
| p200 drafted-vs-plain | EQ | `a816a5d43119b747` | 64 |
| p2k drafted-vs-plain | EQ | `452bfa141a8d1d31` | 64 |
| p2k concurrent-vs-solo (0 background streams decoding after 0.0 s) | EQ | `452bfa141a8d1d31` | 64 |
| resume resumed-vs-fresh | EQ | `f89e6e566098c5c9` | 20 |
| resume repeats | EQ | `f89e6e566098c5c9` | 20 |

Every run reports `drafted 0 rounds 63` and the banner is `drafts off`: the "drafted" arms ran with drafts off, so this
window proves the served path's exactness at 8 x 131,072 bf16 (concurrent equals solo, a resumed prompt equals a fresh
one, repeats equal) but **does not** measure drafter-versus-plain at this shape. That comparison was measured on the FP4
r5 image (`work/DevEnvBoot/RESULT.md`: 184 drafts, drafted equals `"draft": false`), not here, and it stays open for
this image.

## Restore

`RESTORE prod /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 id sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`,
`PROD-IMAGE-OK`, produced by the driver's exit trap.

## What this closes and what it does not

- Closed: step 5's admission at the served window on the as-stored image, with its int4 contract summary and the served
  path's exactness, where the fp8 attempts never reached a boot.
- Open: drafter exactness on this image at this shape (the arm ran drafts off); step 5's three parents and step 6's
  as-stored MTP design, as the port plan lists them.
