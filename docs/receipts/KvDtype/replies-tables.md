# KV dtype: reply equality, dev on bf16 against dev on fp8

labels: D_bf16, D_fp8

## C=1: D_bf16 against D_fp8

| prompt | rows | equal replies | first divergent token | bf16 tokens | fp8 tokens | bf16 token_sha | fp8 token_sha |
|---|---:|---:|---:|---:|---:|---|---|
| code-1k | 1 | 0/1 | 389 | 512 | 512 | 023ab3c6108f | 6d1b4157ff2b |
| code-rec0 | 1 | 0/1 | 3 | 512 | 512 | 1286f533f20e | 9d924b3b9f23 |
| prose-1k | 1 | 0/1 | 32 | 512 | 512 | b4113b29089a | ade912dee557 |
| prose-8k | 1 | 0/1 | 120 | 449 | 407 | 4adc761678df | 0a91d1a3f31d |
| prose-rec0 | 1 | 0/1 | 99 | 512 | 512 | f8bd586c5294 | d1e65310c9a9 |

total C=1: text-equal 0/5, token_sha-equal 0/5

divergences at C=1 (one row a request):

| prompt | j | first divergent token | bf16 token id | fp8 token id | bf16 sha | fp8 sha |
|---|---:|---:|---:|---:|---|---|
| code-1k | 0 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-rec0 | 0 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| prose-1k | 0 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-8k | 0 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-rec0 | 0 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |

prompt-ids code-1k: bf16 1481 fp8 1481 equal True
prompt-ids code-rec0: bf16 33 fp8 33 equal True
prompt-ids prose-1k: bf16 958 fp8 958 equal True
prompt-ids prose-8k: bf16 7997 fp8 7997 equal True
prompt-ids prose-rec0: bf16 40 fp8 40 equal True

## C=2: D_bf16 against D_fp8

| prompt | rows | equal replies | first divergent token | bf16 tokens | fp8 tokens | bf16 token_sha | fp8 token_sha |
|---|---:|---:|---:|---:|---:|---|---|
| code-1k | 2 | 0/2 | 389 | 512 | 512 | 023ab3c6108f | 6d1b4157ff2b |
| code-rec0 | 2 | 0/2 | 3 | 512 | 512 | 1286f533f20e | 9d924b3b9f23 |
| prose-1k | 2 | 0/2 | 32 | 512 | 512 | b4113b29089a | ade912dee557 |
| prose-8k | 2 | 0/2 | 120 | 449 | 407 | 4adc761678df | 0a91d1a3f31d |
| prose-rec0 | 2 | 0/2 | 99 | 512 | 512 | f8bd586c5294 | d1e65310c9a9 |

total C=2: text-equal 0/10, token_sha-equal 0/10

divergences at C=2 (one row a request):

| prompt | j | first divergent token | bf16 token id | fp8 token id | bf16 sha | fp8 sha |
|---|---:|---:|---:|---:|---|---|
| code-1k | 0 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 1 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-rec0 | 0 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 1 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| prose-1k | 0 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 1 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-8k | 0 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 1 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-rec0 | 0 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 1 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |

prompt-ids code-1k: bf16 1481 fp8 1481 equal True
prompt-ids code-rec0: bf16 33 fp8 33 equal True
prompt-ids prose-1k: bf16 958 fp8 958 equal True
prompt-ids prose-8k: bf16 7997 fp8 7997 equal True
prompt-ids prose-rec0: bf16 40 fp8 40 equal True

## C=4: D_bf16 against D_fp8

| prompt | rows | equal replies | first divergent token | bf16 tokens | fp8 tokens | bf16 token_sha | fp8 token_sha |
|---|---:|---:|---:|---:|---:|---|---|
| code-1k | 4 | 0/4 | 389 | 512 | 512 | 023ab3c6108f | 6d1b4157ff2b |
| code-rec0 | 4 | 0/4 | 3 | 512 | 512 | 1286f533f20e | 9d924b3b9f23 |
| prose-1k | 4 | 0/4 | 32 | 512 | 512 | b4113b29089a | ade912dee557 |
| prose-8k | 4 | 0/4 | 120 | 449 | 407 | 4adc761678df | 0a91d1a3f31d |
| prose-rec0 | 4 | 0/4 | 99 | 512 | 512 | f8bd586c5294 | d1e65310c9a9 |

total C=4: text-equal 0/20, token_sha-equal 0/20

divergences at C=4 (one row a request):

| prompt | j | first divergent token | bf16 token id | fp8 token id | bf16 sha | fp8 sha |
|---|---:|---:|---:|---:|---|---|
| code-1k | 0 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 1 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 2 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 3 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-rec0 | 0 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 1 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 2 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 3 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| prose-1k | 0 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 1 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 2 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 3 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-8k | 0 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 1 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 2 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 3 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-rec0 | 0 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 1 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 2 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 3 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |

prompt-ids code-1k: bf16 1481 fp8 1481 equal True
prompt-ids code-rec0: bf16 33 fp8 33 equal True
prompt-ids prose-1k: bf16 958 fp8 958 equal True
prompt-ids prose-8k: bf16 7997 fp8 7997 equal True
prompt-ids prose-rec0: bf16 40 fp8 40 equal True

## C=8: D_bf16 against D_fp8

| prompt | rows | equal replies | first divergent token | bf16 tokens | fp8 tokens | bf16 token_sha | fp8 token_sha |
|---|---:|---:|---:|---:|---:|---|---|
| code-1k | 8 | 0/8 | 389 | 512 | 512 | 023ab3c6108f | 6d1b4157ff2b |
| code-rec0 | 8 | 0/8 | 3 | 512 | 512 | 1286f533f20e | 9d924b3b9f23 |
| prose-1k | 8 | 0/8 | 32 | 512 | 512 | b4113b29089a | ade912dee557 |
| prose-8k | 8 | 0/8 | 120 | 449 | 407 | 4adc761678df | 0a91d1a3f31d |
| prose-rec0 | 8 | 0/8 | 99 | 512 | 512 | f8bd586c5294 | d1e65310c9a9 |

total C=8: text-equal 0/40, token_sha-equal 0/40

divergences at C=8 (one row a request):

| prompt | j | first divergent token | bf16 token id | fp8 token id | bf16 sha | fp8 sha |
|---|---:|---:|---:|---:|---|---|
| code-1k | 0 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 1 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 2 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 3 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 4 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 5 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 6 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-1k | 7 | 389 | 16 | 17 | e49fb88574df | 0e3007668cba |
| code-rec0 | 0 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 1 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 2 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 3 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 4 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 5 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 6 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| code-rec0 | 7 | 3 | 464 | 12237 | b155a24ff768 | 3307e7268814 |
| prose-1k | 0 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 1 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 2 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 3 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 4 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 5 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 6 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-1k | 7 | 32 | 4779 | 7289 | 38cd8862447c | 2d97b319297e |
| prose-8k | 0 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 1 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 2 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 3 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 4 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 5 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 6 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-8k | 7 | 120 | 1121 | 513 | 2998d28161fb | 6726b2d981ba |
| prose-rec0 | 0 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 1 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 2 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 3 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 4 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 5 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 6 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |
| prose-rec0 | 7 | 99 | 28782 | 4221 | e1124b27e7f6 | 7f3dc3312d6c |

prompt-ids code-1k: bf16 1481 fp8 1481 equal True
prompt-ids code-rec0: bf16 33 fp8 33 equal True
prompt-ids prose-1k: bf16 958 fp8 958 equal True
prompt-ids prose-8k: bf16 7997 fp8 7997 equal True
prompt-ids prose-rec0: bf16 40 fp8 40 equal True

## dtype per boot (plan line and container argv)

| cell | plan KV line | argv --kv-cache |
|---|---|---|
| D_bf16 c1 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) | argv --kv-cache=bf16 |
| D_bf16 c2 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) | argv --kv-cache=bf16 |
| D_bf16 c4 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) | argv --kv-cache=bf16 |
| D_bf16 c8 | KV page groups: one page 120.25 MiB, 4096 rows of the full group; full: layers not named, 30.06 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 6 pages, 48.11 MiB padding (6.7 %); snapshot, outside the pool: 110.29 MiB on 1 page, 9.96 MiB padding (8.3 %) | argv --kv-cache=bf16 |
| D_fp8 c1 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) | argv --kv-cache=fp8 |
| D_fp8 c2 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) | argv --kv-cache=fp8 |
| D_fp8 c4 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) | argv --kv-cache=fp8 |
| D_fp8 c8 | KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %) | argv --kv-cache=fp8 |


