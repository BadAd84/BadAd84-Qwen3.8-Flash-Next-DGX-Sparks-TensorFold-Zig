---
name: measure-a-gap-by-arms-on-the-control
description: "Attribute a stack's uniform speed gap to its mechanism(s) by running arms on the CONTROL stack (switch the suspect path off) and separating prefill from decode with per-round counters, before any code is ported."
---

# Attributing a serve speed gap by arms on the control

Use when a rebuilt/ported stack measures slower than production across the board and the env/patch diff alone cannot rank causes.

## The rule that decides it

Do not conclude from the diff. Run an arm **on the control stack** with the suspect mechanism switched off (or forced eager), and an arm **on the candidate stack** with the production mechanism forced on, so each mechanism is isolated from the stack it lives in.

Acceptance of an attribution: the arm reproduces the candidate's number and its replies are byte-equal to the stack it was derived from.

Measured example (Qwen dev `r5dev40` vs production on spark6, same checkpoint):
- `TF_FLASHNEXT_PROMPT_MM=0` on PRODUCTION reproduced the dev engine's cold prefill exactly, replies identical: prefill at 8k/32k, P 2.613/10.459 s, arm 2.930/11.889, dev 2.925/11.767 (arm/dev 1.002, 1.010). Prefill gap = the captured one-program K-sliced prompt matmul.
- Decode in the same arm stayed at parity (D/P 1.000), which by itself proves the prefill and decode gaps are separate mechanisms.

## Decompose decode before blaming drafting

Report tokens per round, rounds a second and ms a round, not just tok/s. If tokens/round is within ~8 percent and flips sign between levels while ms/round is up 6 to 14 percent, the cost is per ROUND (a kernel/launch/glue path), not selective drafting, and no draft-depth or acceptor story holds. The next instrument is a per-round kernel profile of one decode round per engine, not another env arm.

## Traps measured in that window

- Boot-to-boot spread must be measured and stated; an arm inside the control's boot spread is not a win or a loss. A C=1 three-pass prose spread of 20 to 30 percent means only effects above ~3 percent are readable there.
- A banner is not evidence. The production serve is fp8 KV (engine boot line, 1,056 B/position/layer = 1,024 + 32 of scales) while the recipe's banner prints bf16 KV from its own KV_DTYPE default and the argv passes `--kv-cache fp8`. Verify a format claim against the ENGINE's own boot line, never the launcher banner.
- A refusal at load time can make a mechanism unportable as-is: the dev engine refuses a captured kernel set at fp8 KV, and production's set is compiled from another source, so the port must be the FORM into the dev engine's own CUDA (default-off), not the set.
- An arm that changes a boot-time ask (a tier's 6 GiB versus 16 GiB) keeps its decode verdict but can carry a TTFT cost at high concurrency; report the two separately.
- Restore the control serve inside the window's EXIT trap and prove it with health 200, the pinned image id, and the kind-driven env gate (117 rows compared, 0 problems) before calling the window done.
