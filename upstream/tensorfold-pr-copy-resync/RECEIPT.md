# Receipt: copy re-sync and the shared-round copy ramp (port-copy-windows, f738706e0)

Environment: one DGX Spark (GB10, sm_121), kindling spark-os (64 KiB pages), driver 580.178.04, CUDA 13.3
forward-compat userspace; TensorFold v1.2.4 (both arms from the same tip, stock `upab4` and the port `cwab4` on
`ab4b2f05`); checkpoint `nvidia/Qwen3.8-Flash-Next-FP4-Local` @ `b9ce18a6` (NVFP4), `--kv-cache` bf16 (the stock CUDA
Flash Next family keeps bf16 caches), vision off, 131,072-token windows, 1 request at a time for `bench_*`.

## Exactness

Golden: 6/6 identical to the stock build's own replies on every lever cell (both passes). `tools/exact.py` PASS on
both arms at 4 streams with the same six reply shas and the same accepted-draft count (555). Every copy, rewrite and
edit reply sha equal between the arms at 1/2/4/6 streams (0 differing replies).

## The upstream bench (tools/bench_openai.py, 256 tokens, median of 3, one request at a time)

| prompt | stock | port |
|---|---:|---:|
| code (fibonacci) | 73.1 / 73.4 tok/s (2 passes) | 73.0 / 73.0 |
| gpu-chat | 47.0 / 47.0 | 46.7 / 46.9 |

## tools/bench_concurrent.py --alone --serial (aggregate tok/s, code / chat)

| streams | stock | port |
|---|---|---|
| 1 | 73.1 / 46.9 | 72.9 / 46.6 |
| 2 | 138.9 / 86.9 | 138.0 / 86.5 |
| 4 | 243.0 / 155.8 | 241.1 / 155.3 |
| 6 | 305.3 / 304.3 | 304.3 / 209.0 (chat: 208.6) |

Flat within 0.8% at every level; concurrent equals solo on both arms.

## The workloads the change targets (512-token greedy replies, medians of 6 runs, stock / port tok/s)

| workload | stock | port | change |
|---|---:|---:|---|
| one-word rewrite of an 8k context | 230.5 | 300.2 | +30.2% |
| two concurrent edits (stream 1) | 142.1 | 201.5 | +41.7% |
| two concurrent edits (stream 2) | 142.3 | 212.6 | +49.3% |
| edit beside a prose stream (edit) | 148.9 | 234.8 | +57.7% |
| edit beside a prose stream (prose) | 47.8 | 50.2 | +5.0% |
| verbatim copy (1.8k tokens) | 376.4 | 375.9 | -0.1% |

## Settings

`TENSORFOLD_COPY_RESYNC`, `TENSORFOLD_COPY_RESYNC_PROMPT_ONLY`, `TENSORFOLD_COPY_SHARED` (0/1), `TENSORFOLD_COPY_MISS`
(first|keep), `TENSORFOLD_COPY_RAMP` (double|jump). Unset is stock behaviour verbatim; any other value refuses the
start with the setting's name. Receipt boot: 1 / 1 (prompt only) / 1 / keep / jump.

## Gates

`zig fmt --check` clean; `tools/zig/lean_check.py` on each tree separately: 116 problems on base and head, 0 new
(file counts differ by the port's new files); `zig build test --summary all`: head 7701/7768 vs base 7697/7764 with
the identical 3 pre-existing environment failures (a listener test needing a network, two drama_voice_tool cleanup
tests expecting EACCES as root); 2 mutants killed in a scratch copy with the unmutated copy scored first.
