# Boots and environment, window w3

| arm | pass | rc | wall s | par | ctx | overrides | env vars | differs from M1 by |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| EVICT | d | 0 | 37.02 | 2 | 131072 | TF_CACHE_EVICT=decayed_resume | 70 | nothing |
| EVICTb | d | 0 | 36.99 | 2 | 131072 | TF_CACHE_EVICT=decayed_resume | 70 | nothing |
| M1 | d | 0 | 37.02 | 2 | 131072 | none | 70 | nothing |
| M1 | p | 0 | 37.01 | 1 | 131072 | none | 70 | nothing |
| M2 | d | 0 | 36.99 | 2 | 131072 | none | 70 | nothing |
| M2 | p | 0 | 36.98 | 1 | 131072 | none | 70 | nothing |
| P_16384 | p | 0 | 37.03 | 1 | 131072 | TF_FLASHNEXT_CHUNK_SOLO=16384 | 71 | TF_FLASHNEXT_CHUNK_SOLO=16384 |
| P_16384b | p | 0 | 37.00 | 1 | 131072 | TF_FLASHNEXT_CHUNK_SOLO=16384 | 71 | TF_FLASHNEXT_CHUNK_SOLO=16384 |
| P_3072 | p | 0 | 37.01 | 1 | 131072 | TF_FLASHNEXT_CHUNK_SOLO=3072 | 71 | TF_FLASHNEXT_CHUNK_SOLO=3072 |
| P_3072b | p | 0 | 37.02 | 1 | 131072 | TF_FLASHNEXT_CHUNK_SOLO=3072 | 71 | TF_FLASHNEXT_CHUNK_SOLO=3072 |
| P_UNSET | p | 0 | 37.05 | 1 | 131072 | none | 70 | nothing |
| P_UNSETb | p | 0 | 37.02 | 1 | 131072 | none | 70 | nothing |

The environment each boot printed (the container inspect), the base boot first:

Every other arm's list is in its own `env.txt` under `out/<window>/<arm>/<pass>/`.

Foreign requests per arm (requests the arm did not send):

- EVICT d: 0
- EVICTb d: 0
- M1 d: 0
- M1 p: 0
- M2 d: 0
- M2 p: 0
- P_16384 p: 0
- P_16384b p: 0
- P_3072 p: 0
- P_3072b p: 0
- P_UNSET p: 0
- P_UNSETb p: 0
