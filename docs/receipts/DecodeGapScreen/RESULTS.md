# DecodeGapScreen: single-lever decode-gap screen (2026-11-25)

Six single-lever arms bracketed by start/end controls (`D0a`, `D0b`) at `C=8` and `C=1` on `spark6`
(`tensorfold-qwen38:ks41n` `sha256:27b7f3b70d9cb25a...`, `KV_DTYPE=bf16`, `CONTEXT=262144`, `HOST=127.0.0.1`,
KV store cleared before every boot). Window: `2026-11-25T18:50:17Z` to `2026-11-25T19:51:18Z` (`WINDOW-DONE`,
16/16 cells `rc 0`, 16/16 `ARMCHECK OK`, 16/16 `gold 6/6`, 6/6 byte-identical decode reply hashes on every
arm at both `C=8` and `C=1`).

## Control spread (`D0a` vs `D0b`)

- `C=8`: prose `221.8` vs `223.9` (`0.9%`), code `336.6` vs `336.3` (`0.1%`).
- `C=1`: prose `72.2` vs `72.7` (`0.7%`), code `116.7` vs `116.8` (`0.1%`).

## Level C=8

| arm | lever | prose agg | vs D0a | code agg | vs D0a | hashes vs D0a |
|---|---|---:|---:|---:|---:|---|
| D0a | control-start | 221.8 | 1.000 | 336.6 | 1.000 | 6/6 |
| D1 | `TF_FLASHNEXT_ATTN_LANES=1` | 224.6 | **1.013** | 337.8 | **1.004** | 6/6 |
| D2 | `TF_FLASHNEXT_DECODE_GRAPH=1` | 224.8 | **1.014** | 337.3 | **1.002** | 6/6 |
| D3 | `TF_FLASHNEXT_READOUT_FUSE=1` | 222.1 | 1.001 | 337.0 | 1.001 | 6/6 |
| D4 | `TF_QMMF_HALF_BELOW=0` | 225.1 | 1.015 | 336.1 | 0.999 | 6/6 |
| D5 | `TF_FLASHNEXT_SHARED_SIDE=0` | 220.8 | 0.995 | 331.6 | **0.985** | 6/6 |
| D6 | `TF_FLASHNEXT_MTP_WEIGHTS=bf16` | 219.9 | **0.991** | 338.7 | 1.006 | 6/6 |
| D0b | control-end | 223.9 | 1.009 | 336.3 | 0.999 | 6/6 |

## Level C=1

| arm | lever | prose agg | vs D0a | code agg | vs D0a | hashes vs D0a |
|---|---|---:|---:|---:|---:|---|
| D0a | control-start | 72.2 | 1.000 | 116.7 | 1.000 | 6/6 |
| D1 | `TF_FLASHNEXT_ATTN_LANES=1` | 72.5 | 1.004 | 116.5 | 0.998 | 6/6 |
| D2 | `TF_FLASHNEXT_DECODE_GRAPH=1` | 73.1 | **1.012** | 117.7 | **1.009** | 6/6 |
| D3 | `TF_FLASHNEXT_READOUT_FUSE=1` | 73.1 | **1.012** | 117.0 | **1.003** | 6/6 |
| D4 | `TF_QMMF_HALF_BELOW=0` | 72.3 | 1.001 | 116.5 | 0.998 | 6/6 |
| D5 | `TF_FLASHNEXT_SHARED_SIDE=0` | 71.5 | **0.990** | 115.7 | **0.991** | 6/6 |
| D6 | `TF_FLASHNEXT_MTP_WEIGHTS=bf16` | 71.5 | **0.990** | 113.2 | **0.970** | 6/6 |
| D0b | control-end | 72.7 | 1.007 | 116.8 | 1.001 | 6/6 |

## Verdicts

1. **`TF_FLASHNEXT_DECODE_GRAPH=1` (D2) — PROMOTE CANDIDATE:** Beats both controls in all 4 cells (`C=1`
   `73.1 / 117.7` — beating production's `116.1` code at `C=1`; `C=8` `224.8 / 337.3`), 6/6 byte-identical.
   Graduates to full 5-level ABBA + TTFT confirmation (`docs/receipts/DecodeLeversAB/`).
2. **`TF_FLASHNEXT_ATTN_LANES=1` (D1) — PROMOTE CANDIDATE:** Beats both controls at `C=8` (`224.6 / 337.8`,
   code +0.4% at 4x control spread), level at `C=1` (multi-stream lever), 6/6 byte-identical. Graduates to
   full 5-level ABBA + TTFT confirmation (`docs/receipts/DecodeLeversAB/`).
3. **`TF_FLASHNEXT_READOUT_FUSE=1` (D3) — SMALL EXACT WIN:** Beats both controls at `C=1` (`73.1 / 117.0`)
   and level-to-positive at `C=8` (`222.1 / 337.0`), 6/6 byte-identical.
4. **`TF_FLASHNEXT_SHARED_SIDE=0` (D5) — REFUTED:** Loses in all 4 cells (`-0.5%` to `-1.5%`). Confirms
   the current default `TF_FLASHNEXT_SHARED_SIDE=1` is a real win.
5. **`TF_FLASHNEXT_MTP_WEIGHTS=bf16` (D6) — REFUTED:** Loses `-3.0%` code and `-1.0%` prose at `C=1`,
   `-0.9%` prose at `C=8`. Confirms `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` on r5 (clears the r5 drafter A/B debt).
6. **`TF_QMMF_HALF_BELOW=0` (D4) — LEVEL:** Inside spread on code at both levels (`-0.1%` / `-0.2%`).

Raw artefacts live on `spark6:~/work/dgs/out/`.
