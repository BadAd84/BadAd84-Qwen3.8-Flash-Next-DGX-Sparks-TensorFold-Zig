# GB10 thermal behaviour and benchmark methodology (measured 2026-10-24)

How a DGX Spark GB10 behaves under sustained GPU load, and what that forces on every speed number
measured for the Qwen serve (spark4 Python production, spark6 Zig comparison - spark6 is one of the
measured boxes). Measured 2026-10-24 on spark4, spark5 and spark6: idle boxes, sustained dense BF16
GEMM 8192^3 in ~5 s chunks with per-chunk clock/power/temp sampling, torch 2.13.0a0+nv26.07, driver
580.178.04; all three boxes agreed within 1.5% on every metric. The fleet-wide hardware investigation
(power limits, firmware signing, the PD wedge) lives in the omp skill
`tune-dgx-spark-gb10-gpu-power-and-throttling`; this doc is the part that changes how benchmarks are
run and read.

## The sustained envelope

| Box state under load | Clock | Power | Temp |
|---|---|---|---|
| Fresh/cool, start of load | 2327-2372 MHz | ~92-94 W | 56-57 C |
| After ~50 s sustained | 2249-2268 MHz (clock -4%) | ~89-90 W | 68-71 C |
| Multi-minute / heat-soaked | ~2170-2200 MHz | 86-90 W | 80-83 C |

- `clocks_event_reasons` stays **0x0 throughout**: the sag is the DVFS power/voltage curve following
  temperature, not a reported cap. There is no throttle event to detect - only the clock number moves,
  so a benchmark that logs only tok/s hides the drift entirely.
- Peak compute measured on the same runs: dense BF16 GEMM with FP32 accumulate 96-97.5 TFLOPS
  sustained (97% of the clock-scaled 125 TFLOPS dense spec), FP8 ~194 TFLOPS, memcpy 219-231 GB/s
  against the 273 GB/s spec. GB10 runs at full tensor issue rate - there is no hidden limit to
  unlock, and clock locking cannot raise any of it (below).

## Rules for speed benchmarks on GB10

1. **Thermal state is a confound.** The same code on a heat-soaked box reads up to ~4-6% low versus a
   cool box; clock sag alone is ~4% from fresh to 50 s and more by minute two.
2. **Interleave A/B arms** (A,B,A,B,...) or equalise start temperatures between arms; never compare
   arm-1-then-arm-2 runs from differently-hot boxes.
3. **Record the GPU temp (and `clocks.sm` where possible) at the start of every timed window.** A
   benchmark log without its start temperature cannot be re-interpreted later.
4. Warm-up is mandatory but not sufficient: warmed caches and kernels are good, soaked silicon costs
   clocks. Keep warm-ups short and identical across arms.
5. Prefill / compute-bound numbers are the sensitive ones (clocks scale them directly); decode
   (bandwidth-bound, ~230 GB/s achieved) is far less clock-sensitive.
6. Note node uptime with every benchmark (the existing power-drift rule; a full power-off, not a warm
   reboot, is what resets it).

## Clock locking is not a lever (measured 2026-10-24)

`nvidia-smi -lgc` accepts locks of 2600 / 2800 / 3003 MHz ("All done") but the governor never
delivers more than ~2275 MHz sustained; power stays 86-93 W; and locking measured slightly WORSE
(97.1 -> 94.7-95.5 TFLOPS sustained) and hotter than leaving it alone. The "Applications Clocks
2418 MHz" default is the validated burst peak; "Max Clocks 3003 MHz" is unreachable under sustained
load on this power envelope. A lock is only ever useful to LOWER a ceiling (thermal capping), never
to raise sustained clocks - do not spend benchmark time on it. (`adam` cannot run `-lgc` on the
Sparks; a `--privileged` container can - now irrelevant for raising anything.)

## Reproducing the measurement

```
docker run --rm --gpus all -v /tmp/probe.py:/tmp/probe.py --entrypoint python3 <ai-engine image> /tmp/probe.py
# probe: sustained bf16 matmul 8192^3 in ~5 s chunks; after each chunk sample
# nvidia-smi --query-gpu=clocks.sm,power.draw,temperature.gpu,clocks_event_reasons.active --format=csv,noheader
```
