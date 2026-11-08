Title: flashnext: declare warm turns, so a reply's background pass can prefill the next turn's prompt

Body:

## What this changes

The lane core runs warm turns end to end: after a chat reply, `server/warm.zig` prefills the next turn's
prompt in the background, and `lane_host_warm.zig` pre-empts the pass at any chunk when real work arrives.
The mechanism is offered to any family that declares `warm_quiet`; until now only `nemotron` declared it,
and `cuda_startup_phase.zig` hard-coded Nemotron's quiet constant - so a Flash Next serve never warmed.

This change adds the two declarations to the Flash Next CUDA family (`warm_quiet = 150 ms`,
`warm_opt_in = true`), moves the quiet window through `api.Info.warm_quiet_ns` instead of the hard-coded
constant, and reads `TENSORFOLD_WARM_TURNS` strictly: exactly "1" or "0" (or unset/empty) - any other
value refuses the start with the setting's name. Off by default; a default boot is unchanged.

## Why

A follow-up turn's prompt is known the moment the previous reply ends. Prefilling it in the background
moves almost all of the next turn's prefill off the critical path: on one GB10 (NVFP4 checkpoint, bf16 KV,
131,072-token windows) the next-turn time to first token at temperature 0 fell 38-45% at 1 and 2 streams,
with the second turn's prompt fully cached by the time it arrives (measured rows: 100,782 of 100,802 at
100k).

## The trade, measured

A fresh prompt sent while the warm pass holds the GPU waits for it. At a 0.2 s pause after the reply, a
cold 8k prompt's time to first token rose 8.6% at one stream and 6.3% at two; at 1.0 s and 3.0 s pauses
the difference is within noise (the 150 ms quiet window plus the prefill fits inside a second). The
setting is off by default, so the trade is opt-in per serve.

## Checks on this head

- Head commit: `ed50016cdf`, on upstream `267c5af6a`. Both arms of the A/B built from that tip.
- Lean checker, each tree with its own copy: 116 problems on base and head, 0 new.
- Tests: `zig build test --summary all` with no GPU and no network: base and head build the same steps
  with the identical failing-test list (one listener test that needs a network, two `drama_voice_tool`
  cleanup tests that expect `error.AccessDenied` as root) and equal per-test pass counts.
- Boxes it reaches: one NVIDIA GB10 (DGX Spark class), CUDA. Not run: Metal, HIP and XPU host tests
  (this box is CUDA only), and any GPU kernel contract (no kernel changes).
- Exactness: golden 6/6 identical on every cell (the port's replies equal stock's own replies, 24 boots
  across 6 cells), and every copy, rewrite and edit reply hash equal between the arms.
- Decode, idle/loaded TTFT, and the copy, rewrite and edit workloads are equal on all arms within the
  boot spread; the memory line in the boot log is unchanged (the `nvidia-smi` memory query is not
  available on GB10, so the allocator's own line is the record).
- Boot cost: 0-4 s on the warm-on arm.

## Measurement

One fresh boot per cell, ABBA order, medians over two boots a cell at 1 and 2 streams; next-turn time to
first token from the client at temperature 0; the trade cell sends a fresh 8k prompt at a fixed pause
after each reply. Raw cells and the summariser are on the measurement box; the numbers here are the
medians the tools printed.

## Checklist

- [x] The title and description match the head commit and the measurement.
- [x] The setting is strict: an unknown value refuses the start with its name, and unset means exactly
      today's behaviour.
- [x] Comments and docstrings are one line. No measurements or history in the source.
- [x] No personal data, machine names, internal hosts or local paths in the diff or its commits.
- [x] Drafted output equals `"draft": false`, and concurrent equals solo, on both arms.
- [x] No precision traded for speed: the warm pass prefills prompts and changes no arithmetic.
