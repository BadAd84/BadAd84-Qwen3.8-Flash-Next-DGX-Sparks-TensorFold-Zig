# The int4 contract on a GB10: device receipt for the rebased head

Head `984556bf50ac4e603695596444772f27bd93bd01` (branch `cuda-int4-respond`, six signed commits on upstream main
`7bd7081e061ca22e3431d2342cd66104dd5fe320`). Built and run on spark6 (NVIDIA GB10, sm_121, driver 580.178.04) inside
one hold of `~/work/gpu.lock`, in the CUDA 13.3 build container, with production stopped for the window and restored
and proved after it.

Verdict: `int4-contract` is green on the device with the count the lane expected, both planted controls red at the
gates they are planted for, and the prompt-down BF16 form bit-equal to the plain bf16 down on all seven shapes (as
are the prompt-down FP32 and prompt gate/up forms). The limits audit reports no int4 problem: every int4 record is
current and passes on all five SMs, and both limiter controls are red on every SM. Its nonzero problem count is 550
stale records elsewhere in the tree, each counted by the audit's own design and none a launch past a limit.

## Boot and production at the start (the box reset at 12:15)

| reading | value |
|---|---|
| `uptime -s` | `2026-11-23 12:15:10` (the box hard-reset; the first window died with it) |
| previous boot, last journal line | `Nov 23 12:11:30 ... Starting spark-dmesg-snapshot.service`, then nothing |
| previous boot memory 30 s before | `MemTotal=126692 MemFree=56804 MemAvailable=81423 ... date=2026-11-23T12:11:30Z` |
| OOM in the previous boot's last minutes | none (the only OOM entries are from Oct 26 and Nov 15) |
| watchdog give-up record | `/var/lib/spark-watchdog/resets` empty |
| production when the window took the lock | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, id `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`, `/health` 200 |

The reset cause is not established from the box's own records: no OOM, no panic line, no watchdog give-up, 81 GiB
available 30 s earlier. The window log before the reset shows the runner alive at 104 percent of one core, GPU idle,
32.7 GiB in the container. The requeue therefore changed three things: fresh extract, fresh zig caches, and a 96 GiB
memory cap on the build container so a runaway host allocation kills the container rather than the box. It did not
recur: the same heavy kernel ran again with the container steady at 31.8 GiB.

## Tree identity, verified both ways before any build

| item | value |
|---|---|
| archive | `in/head.tar.gz`, 43,637,580 bytes, sha256 `588174d9ce43d39ceb5055cc2313949b5679e7cd73325fce2d4c4830dda33ea3` (laptop) |
| sha256 after scp, on spark6 | `588174d9ce43d39ceb5055cc2313949b5679e7cd73325fce2d4c4830dda33ea3` (equal) |
| extracted tree against `git ls-tree -r` manifest, pre-lock | `files 13489 mismatches 0 extras 0` |
| the same verification again inside the lock, from a fresh extract | `files 13489 mismatches 0 extras 0` |

## Toolchain

Container `tensorfold-qwen38:zig-db28187` (Ubuntu 24.04, CUDA 13.3 V13.3.73 at `/usr/local/cuda/bin/nvcc`), Zig
0.17.0 from `/home/adam/zigtools` mounted at `/opt/zig`, run with `--gpus all --user 1000:1000 --memory=96g`, fresh
global cache. Preflight `zig build --help` in that container listed the steps used: `int4-contract`,
`kernel-contract`, `kernel-contract-fatbins`, `fatbins`, `compile-cuda-tests`.

## Steps, with every exit status

| step | command | rc | wall | summary |
|---|---|---|---|---|
| 01 | `zig build --summary all int4-contract -Dnvcc=/usr/local/cuda/bin/nvcc` | 0 | 486 s | `SUMMARY int4: 8 kernels, 8 pass gates 1-4, 0 fail, 0 known findings; 2 controls: 2 red as planted, 0 missed` |
| 03 | `zig build --summary all fatbins kernel-contract-fatbins -Dnvcc=... -Dsm=80,86,89,120,121` | 0 | 657 s | `Build Summary: 358/358 steps succeeded`; 174 images in `zig-out/fatbin` |
| 04 | the runner with no command (usage) | 2 | 1 s | the usage line names `int4-contract` |
| 05 | the runner, `kernel-contract-limits zig-out/fatbin` | 1 | 50 s | `FAIL kernel-contract-limits: 550 problems` (all stale records, below) |
| 02 | `zig build --summary all kernel-contract -Dnvcc=/usr/local/cuda/bin/nvcc` | 137 | 4083 s | stopped by the operator, no summary line; state below |

Steps 04 and 05 first ran with rc 127 because the driver passed the runner's host path into the container, where
only `/tf` is mounted. They were re-run with the container path (`/tf/.zig-cache/o/a239b0a9.../tf-cuda-test`) and the
rows are those re-runs. Both attempts are kept: `04-usage.log` and `05-limits.log` are the 127s,
`04-usage-fixed.log` and `05-limits-fixed.log` the receipts.

## The int4 receipt: the count the lane expected

`SUMMARY int4: 8 kernels, 8 pass gates 1-4, 0 fail, 0 known findings; 2 controls: 2 red as planted, 0 missed`

Eight kernels and two controls is what the tree implies: `entries` holds 10 rows, 2 of them `control:`, and
`gates.runAll` counts a control in `controls` and every other kernel in `kernels`. The line printed that exactly, so
nothing had to be reconciled.

### Gate 3, byte for byte against the plain forms

```
PASS shapes cuda int4 routed down to bf16 (int4_prompt_kernel, 64-pair items): 7 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
PASS shapes cuda int4 routed down to fp32 (int4_prompt_kernel, 64-pair items): 7 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
PASS shapes cuda int4 routed gate/up SwiGLU (int4_prompt_kernel, 64-pair items): 8 shapes bit-equal to the kernel it replaces (worst 0.000 of the bound), 0 edges refused by the kernel
```

The BF16 prompt-down entry compares its bytes to `int4.down(..., false, ..., plan_tile)`, the plain bf16 down, at
the two served shapes (64 and 200 token rows at 2,560 by 640) and the five edges: seven shapes, all identical. The
FP32 prompt-down and the prompt gate/up forms are compared by the same hook to their own plain baselines.

### The two planted controls, red where planted

```
CONTROL control: int4 routed down with each group's sum rounded to bf16: red at sums, as planted
CONTROL control: int4 lm head with each word's nibbles unshuffled: red at shapes, as planted
```

Their detection text, which is the only FAIL-shaped output in the run:

```
FAIL sums control: int4 routed down with each group's sum rounded to bf16: 1103940812.8x over its exact-sum bound at k 640: not fp32 sums (fp16 would miss 96087692x, bf16 640330411x)
FAIL shapes control: int4 lm head with each word's nibbles unshuffled: at 1x2560x2560 output 0 is 4.650000e1 where float64 gives 2.521465e0: 1301.67 of its bound
```

### The skipped expert's rows

```
PASS int4 skipped slot: 16 of 96 pair rows left at 0xff, the others byte-equal to the all-live run
```

## The limits audit

```
FAIL kernel-contract-limits: 550 problems
```

What the 550 are, from the audit's own output and its own counter:

| count | value |
|---|---|
| per-launch lines | 5941 `PASS`, 0 `FAIL limits` |
| `(record stale)` lines | 550, exactly the count reported (`if (!control and !current) n += 1` in `contract_limits.zig`) |
| limiter controls | 10 `RED` (both controls on all five SMs), 0 `MISSED` |
| `RECORD` lines | 1739 |
| int4 | 105 `PASS` (21 launches on five SMs), 21 `RECORD`, 0 stale, 0 failing |

No launch, int4 or otherwise, is past a limit on this build. The audit's nonzero count is one per record whose
recorded usage differs from what this nvcc build compiles, and every int4 record is current. The tree was not
touched to make the audit read zero; the number is reported as printed.

## The full registry run (step 02), stopped part way

`zig build --summary all kernel-contract` ran for 4083 s and was stopped by the operator, so it printed no summary
line. Why it was stopped: the required receipt (step 01), the limits images (03) and the audit (04, 05) were all
complete, and the GPU lock was next in line for another lane's queued stages. At the stop it had re-entered the moss
image decoder `shapes` gate, the one the first window was inside when the box reset, with the container steady at
31.8 GiB; the gate itself was still running.

Its state when stopped, with every line accounted for:

| count | value |
|---|---|
| `PASS` lines | 2452 |
| `FAIL` lines | 441 = 430 control detections plus 11 known findings |
| `CONTROL` lines | 430, of which 0 missed (each control prints its FAIL why-line and then `CONTROL ...: red at <gate>, as planted`) |
| `KNOWN` lines | 11 (qwen35 attention variants, glm score variants) |
| real kernel failures | 0: 430 + 11 = 441 |

So in the 2452 gates that did run, no kernel failed except through the declared known findings. Two things this run
did not reach: the trailing standalone suites and the in-process gate 5 limits section, and the registry kernels
after the moss image family.

## Production restore, proved

```
RESTORE health=200 waited_s=95 image=tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 id=sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f mem=total 123 GiB, available 35 GiB df=/dev/nvme0n1p2 916G 745G 124G 86% /home boot=2026-11-23 12:15:10
PROD-IMAGE-OK tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f health=200
```

After that the next lane took the lock and restarted the same container for its own stage (container `StartedAt`
13:50:24); a probe at 13:51:52 read `/health` 200 on the pinned image and id. Only containers carrying this window's
own `int4device=1` label were removed; nothing else was signalled. No sparkDash process or service exists on spark6
(check-only: `spark-agent.service`, `mentatd`, and the hardware `spark-watchdog` were left as found and untouched).

## Disk

| point | value |
|---|---|
| before the window | `/dev/nvme0n1p2 916G 743G 127G 86% /home` |
| after production stopped | 123 GiB total, 6 used, 117 available |
| in the window log at restore | `916G 745G 124G 86% /home`, scratch `BOX 3.6G` |
| after teardown | `916G 742G 128G 86% /home`, `~/work/Int4Device` removed and recorded in `~/INVENTORY.md` |

## What the first window produced before the reset

Kept in `out/`: the same step 01 verdict (rc 0, 438 s, the same SUMMARY line and the same gate 3 and control lines)
and a partial full run at 2452 `PASS`, 11 `KNOWN`, no summary. Nothing from that window is used as the receipt here;
the requeue re-produced step 01 from a fresh extract.

## Anything unrun

- The full registry run's summary line (stopped as described; its 2452 gates are accounted above).
- The build box's host gate table is that lane's own row set and is not claimed here.
- Nothing else: the int4 suite, both controls, gate 3 on the three prompt forms and the limits audit all ran on this
  GB10.

Logs: `out2/` (the requeued window: `01-int4-contract.log`, `01-summary.txt`, `01-gate-lines.txt`,
`03-fatbins.log`, `04-usage-fixed.log`, `05-limits-fixed.log`, `02-kernel-contract.log`, `steps.tsv`, `window.log`,
`prod-restore.txt`, `WINDOW2-DONE`, `tree-verify.txt`) and `out/` (the first window).
