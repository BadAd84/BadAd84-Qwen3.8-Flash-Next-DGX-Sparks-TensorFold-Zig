# 0041 A/B results: the 64-column fused prompt tile (`TF_FLASHNEXT_PROMPT_KS_N`)

**Verdict: REFUTED.** The 64-column prompt tile (`F1: KS_N=64, GROUP=8` and `F2: KS_N=64, GROUP=0`) is
byte-identical to the engine's 128-column prompt tile (`F0: KS_N=0`) at every concurrency level (30/30
decode reply hashes equal, 15/15 golden 6/6), and does **not** reproduce production's cold-prefill lead
(`+0.31 s` at 8k, `+1.31 s` at 32k from ParityGap A2). Over all five concurrency levels (`C=1, 2, 4, 6, 8`),
`F1` is `1.006` at cold 8k and `1.004` at cold 32k against `F0` (level to slightly slower; `+6.3%` slower at
`C=8` cold 8k), and `F2` is `0.991` at cold 8k and `1.000` at cold 32k (level).

Per `AB-PLAN.md` ("What the numbers confirm or refute"): `F1` is at or above `F0` at both prompt sizes, so
the 64-column block and `GROUP=8` band schedule buy nothing on this engine; the captured Triton kernel's
cold-prefill advantage is its staging/code-generation rather than its column block. `TF_FLASHNEXT_PROMPT_KS_N`
and `TF_FLASHNEXT_PROMPT_KS_GROUP` remain `0` (default off) in `dev.env` and are not promoted.

## Window provenance

- **Host:** `spark6` (`7.0.0-1019-nvidia-64k`, Ubuntu 24.04.5 LTS, NVIDIA GB10, driver `580.178.04`, 123 GiB RAM).
- **Image:** `tensorfold-qwen38:ks41n` (`sha256:27b7f3b70d9cb25a4301a0c4ae7f812eb102893c12336030c63290b4a4215e55`,
  41 patches of `patches/main-1ece6e6db-r5-dev` applied to `1ece6e6d`, relabeled `tf.kernels=embedded`).
- **Shape:** `CHECKPOINT=int4`, `VISION=0`, `KV_DTYPE=bf16` (the dev launcher's exact-KV default),
  `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`, persistent KV tier on (`--prompt-cache-gib 6 --prompt-cache-disk /cache/kv
  --learn-gib 60`), `CONTEXT=262144`, `HOST=127.0.0.1`, KV store cleared before every boot.
- **Window:** `2026-11-25T17:13:47Z` to `2026-11-25T18:39:27Z` (`WINDOW-DONE`, 15 cells, `rc 0` on all 15).
- **Proof of isolation:** Every cell passed `ARMCHECK` (`F0`: `TENSORFOLD_CUDA_KERNELS=native`, no
  `prompt matmuls:` line; `F1`: `KS_N=64`, `KS_GROUP=8`, `prompt matmuls: ... 64-column blocks, 8 row tiles a band`;
  `F2`: `KS_N=64`, `prompt matmuls: ... 64-column blocks, 0 row tiles a band`).
- **Exactness:** Golden 6/6 identical to `zgold-base-c1.json` on all 15 boots. Greedy decode reply hashes
  (`dec.log` `TOK` lines, 3 prose + 3 code passes per cell):
  - `C=1`: `F1 == F0` 6/6, `F2 == F0` 6/6
  - `C=2`: `F1 == F0` 6/6, `F2 == F0` 6/6
  - `C=4`: `F1 == F0` 6/6, `F2 == F0` 6/6
  - `C=6`: `F1 == F0` 6/6, `F2 == F0` 6/6
  - `C=8`: `F1 == F0` 6/6, `F2 == F0` 6/6

## Geometric mean against F0 across all five levels (`C=1, 2, 4, 6, 8`)

| arm | lever | levels | decode vs F0 | cold8k vs F0 | cold32k vs F0 |
|---|---|---|---:|---:|---:|
| F1 | `KS_N=64 GROUP=8` | 1,2,4,6,8 | 1.014 | 1.006 | 1.004 |
| F2 | `KS_N=64 GROUP=0` | 1,2,4,6,8 | 1.009 | 0.991 | 1.000 |

(Ratios are `arm / F0`: above `1.000` is faster for decode; below `1.000` is faster for TTFT.)

## Decode and TTFT per arm and level

| level | arm | prose agg | vs F0 | code agg | vs F0 | tok/round p | c | accept p | c | cold8k vs F0 | cold32k vs F0 |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | F0 | 69.0 | 1.000 | 113.3 | 1.000 | 2.73 | 5.77 | 0.734 | 0.731 | 1.000 | 1.000 |
| 1 | F1 | 71.9 | 1.042 | 116.3 | 1.026 | 2.73 | 5.77 | 0.734 | 0.731 | 0.973 | 1.003 |
| 1 | F2 | 72.9 | 1.057 | 117.1 | 1.034 | 2.73 | 5.77 | 0.734 | 0.731 | 0.975 | 1.004 |
| 2 | F0 | 101.9 | 1.000 | 170.3 | 1.000 | 2.51 | 5.33 | 0.741 | 0.750 | 1.000 | 1.000 |
| 2 | F1 | 103.8 | 1.019 | 172.8 | 1.015 | 2.51 | 5.33 | 0.741 | 0.750 | 1.006 | 1.005 |
| 2 | F2 | 104.1 | 1.022 | 171.9 | 1.009 | 2.51 | 5.33 | 0.741 | 0.750 | 0.993 | 1.002 |
| 4 | F0 | 157.9 | 1.000 | 245.8 | 1.000 | 2.53 | 5.26 | 0.734 | 0.760 | 1.000 | 1.000 |
| 4 | F1 | 158.2 | 1.002 | 246.5 | 1.003 | 2.53 | 5.26 | 0.734 | 0.760 | 0.999 | 1.000 |
| 4 | F2 | 157.5 | 0.997 | 244.8 | 0.996 | 2.53 | 5.26 | 0.734 | 0.760 | 1.002 | 1.002 |
| 6 | F0 | 190.5 | 1.000 | 292.9 | 1.000 | 2.52 | 4.92 | 0.726 | 0.791 | 1.000 | 1.000 |
| 6 | F1 | 189.8 | 0.996 | 291.9 | 0.997 | 2.52 | 4.92 | 0.726 | 0.791 | 0.991 | 1.004 |
| 6 | F2 | 189.2 | 0.993 | 292.5 | 0.999 | 2.52 | 4.92 | 0.726 | 0.791 | 0.997 | 1.009 |
| 8 | F0 | 215.8 | 1.000 | 336.6 | 1.000 | 2.54 | 4.90 | 0.723 | 0.793 | 1.000 | 1.000 |
| 8 | F1 | 223.3 | 1.035 | 338.2 | 1.005 | 2.54 | 4.90 | 0.723 | 0.793 | 1.063 | 1.009 |
| 8 | F2 | 213.4 | 0.989 | 335.3 | 0.996 | 2.54 | 4.90 | 0.723 | 0.793 | 0.989 | 0.985 |

## Cold TTFT (median of 2, idle) and warm turn, seconds

| level | arm | cold1k-off | cold8k-off | cold8k-on | cold32k-off | cold32k-on | warm2k |
|---:|---|---:|---:|---:|---:|---:|---:|
| 1 | F0 | 0.619 | 3.060 | 3.010 | 11.886 | 12.016 | 1.318 |
| 1 | F1 | 0.600 | 2.978 | 2.950 | 11.922 | 11.989 | 1.263 |
| 1 | F2 | 0.633 | 2.982 | 3.022 | 11.931 | 11.977 | 1.256 |
| 2 | F0 | 0.609 | 2.987 | 2.960 | 11.944 | 12.044 | 1.266 |
| 2 | F1 | 0.607 | 3.005 | 2.958 | 12.002 | 12.062 | 1.255 |
| 2 | F2 | 0.603 | 2.967 | 2.998 | 11.962 | 11.995 | 1.237 |
| 4 | F0 | 0.607 | 2.993 | 2.971 | 11.928 | 12.153 | 1.388 |
| 4 | F1 | 0.624 | 2.989 | 2.996 | 11.933 | 12.018 | 1.265 |
| 4 | F2 | 0.617 | 2.998 | 3.026 | 11.947 | 12.077 | 1.370 |
| 6 | F0 | 0.632 | 3.020 | 2.990 | 11.913 | 12.059 | 1.321 |
| 6 | F1 | 0.618 | 2.993 | 3.024 | 11.962 | 12.088 | 1.316 |
| 6 | F2 | 0.618 | 3.011 | 3.030 | 12.024 | 12.120 | 1.331 |
| 8 | F0 | 0.630 | 3.087 | 3.118 | 12.157 | 12.116 | 1.381 |
| 8 | F1 | 0.665 | 3.283 | 3.193 | 12.266 | 12.157 | 1.426 |
| 8 | F2 | 0.649 | 3.053 | 3.068 | 11.977 | 12.055 | 1.394 |

Raw artefacts live on `spark6:~/work/pks/out/`.
