# DecodeLeversAB: 5-level (`C=1, 2, 4, 6, 8`) promotion A/B for `DECODE_GRAPH=1` and `ATTN_LANES=1`

**Verdict: BOTH MEASURED-LEVEL — DO NOT PROMOTE.** Over all five concurrency levels (`C=1, 2, 4, 6, 8`),
both `G1` (`TF_FLASHNEXT_DECODE_GRAPH=1`) and `A1` (`TF_FLASHNEXT_ATTN_LANES=1`) are byte-identical to
control `B0` (30/30 decode reply hashes equal, 15/15 golden 6/6) and level on both decode and TTFT:
- `G1` (`DECODE_GRAPH=1`) vs `B0`: decode geomean `1.001` (prose `1.000`, code `1.002`), `cold8k 0.997`,
  `cold32k 1.000`, `warm2k 1.009`.
- `A1` (`ATTN_LANES=1`) vs `B0`: decode geomean `1.003` (prose `1.003`, code `1.002`; `+2.8%` prose /
  `+0.9%` code at `C=8`, `-1.8%` prose at `C=4`, `-1.1%` prose at `C=1`), `cold8k 1.001`, `cold32k 1.000`,
  `warm2k 1.017`.

Both remain `0` in `dev.env`.

## Window provenance

- **Host:** `spark6` (`7.0.0-1019-nvidia-64k`, NVIDIA GB10, driver `580.178.04`).
- **Image:** `tensorfold-qwen38:ks41n` (`sha256:27b7f3b70d9cb25a4301a0c4ae7f812eb102893c12336030c63290b4a4215e55`).
- **Shape:** `CHECKPOINT=int4`, `VISION=0`, `KV_DTYPE=bf16`, `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`, persistent KV
  tier on, `CONTEXT=262144`, `HOST=127.0.0.1`, KV store cleared before every boot, no production restore on
  exit (owner 2026-11-25).
- **Window:** `2026-11-25T20:03:19Z` to `2026-11-25T21:28:58Z` (`WINDOW-DONE`, 15/15 cells `rc 0`, 15/15
  `ARMCHECK OK`, 15/15 `gold 6/6`, 30/30 reply hashes byte-identical to `B0`).
- **Interleaved order:** `C=1: B0 G1 A1`, `C=8: A1 G1 B0`, `C=2: B0 G1 A1`, `C=4: A1 G1 B0`, `C=6: B0 G1 A1`.

## Geometric mean against `B0` over all five levels (`C=1, 2, 4, 6, 8`)

| arm | lever | levels | prose vs B0 | code vs B0 | decode vs B0 | cold8k vs B0 | cold32k vs B0 | warm2k vs B0 |
|---|---|---|---:|---:|---:|---:|---:|---:|
| G1 | `TF_FLASHNEXT_DECODE_GRAPH=1` | 1,2,4,6,8 | 1.000 | 1.002 | 1.001 | 0.997 | 1.000 | 1.009 |
| A1 | `TF_FLASHNEXT_ATTN_LANES=1` | 1,2,4,6,8 | 1.003 | 1.002 | 1.003 | 1.001 | 1.000 | 1.017 |

## Per-level decode and TTFT

| level | arm | prose agg | vs B0 | code agg | vs B0 | cold8k vs B0 | cold32k vs B0 | warm2k vs B0 | hashes vs B0 |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---|
| 1 | B0 | 73.0 | 1.000 | 117.6 | 1.000 | 1.000 | 1.000 | 1.000 | 6/6 |
| 1 | G1 | 72.6 | 0.995 | 117.9 | 1.003 | 1.005 | 1.006 | 1.010 | 6/6 |
| 1 | A1 | 72.2 | 0.989 | 117.1 | 0.996 | 0.997 | 1.008 | 1.017 | 6/6 |
| 2 | B0 | 101.6 | 1.000 | 170.1 | 1.000 | 1.000 | 1.000 | 1.000 | 6/6 |
| 2 | G1 | 103.2 | 1.016 | 171.4 | 1.008 | 1.000 | 0.997 | 0.979 | 6/6 |
| 2 | A1 | 103.4 | 1.018 | 171.4 | 1.008 | 0.990 | 0.995 | 1.013 | 6/6 |
| 4 | B0 | 158.0 | 1.000 | 246.7 | 1.000 | 1.000 | 1.000 | 1.000 | 6/6 |
| 4 | G1 | 158.4 | 1.003 | 245.6 | 0.996 | 0.982 | 0.995 | 1.020 | 6/6 |
| 4 | A1 | 155.1 | 0.982 | 245.6 | 0.996 | 0.997 | 0.997 | 0.998 | 6/6 |
| 6 | B0 | 188.9 | 1.000 | 291.3 | 1.000 | 1.000 | 1.000 | 1.000 | 6/6 |
| 6 | G1 | 189.0 | 1.001 | 292.3 | 1.003 | 1.005 | 0.999 | 1.032 | 6/6 |
| 6 | A1 | 188.9 | 1.000 | 292.4 | 1.004 | 1.007 | 1.004 | 1.026 | 6/6 |
| 8 | B0 | 216.4 | 1.000 | 332.7 | 1.000 | 1.000 | 1.000 | 1.000 | 6/6 |
| 8 | G1 | 213.1 | 0.985 | 332.7 | 1.000 | 0.994 | 1.000 | 1.006 | 6/6 |
| 8 | A1 | 222.4 | 1.028 | 335.8 | 1.009 | 1.014 | 0.996 | 1.031 | 6/6 |

Raw artefacts live on `spark6:~/work/dlab/out/`.
