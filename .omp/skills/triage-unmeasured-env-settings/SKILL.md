---
name: triage-unmeasured-env-settings
description: "Use when an env register or settings list appears to demand a full sweep: check env membership first, subtract what the sweep records already cover, classify the rest by effect, and boot only the real candidates."
---

# Triage an env list before sweeping any of it

The five-level rule is for candidates, not for every name an engine's table carries. Applying it to a whole env list is hundreds of boots; triaging the list first is minutes.

## Order of work

1. **Read the env file, not the register.** Count `NAME=` lines in `scripts/env/dev.env` (or the serve's equivalent). A register that lists settings as "debt" or "unset" is frequently stale after a completion pass: check membership before believing absence. On the GLM serve, 69 settings the register called debt were all already in the file.

2. **Subtract everything already measured.** Grep each name against the sweep records: the knobs document with its cells, the provenance dossier with its classes, and the queue row directories. Anything found has a verdict, a cell set or a recorded rejection, and needs no new boot.

3. **Classify the remainder by what the setting can even affect**, because most of what is left cannot move throughput:
   - other model families (a Qwen or FlashNext name on a GLM serve) and vision/PDF/video/grammar paths: unreachable, record the reason;
   - logging, tracing, receipts, timing, device-check flags: diagnostics, no throughput claim;
   - boot, device, CUDA, memory-reserve and carveout plumbing: measured once at boot or by a memory-fit check, never at five levels;
   - capacity settings (context ceilings, KV host budget): capacity, not speed;
   - disk-tier restore and prefetch settings: they belong to that tier's own qualification, not to a decode sweep.

4. **The remainder is the candidate list.** Group by family so one boot can test several settings that cannot interact, and name the rule before the rows. On the GLM serve this left 6 candidates from 119 settings: drafter confidence and node count, prompt steps and shared admission, the link wait, and the host cache.

## What to record instead of a sweep

Every name that does not get a boot gets a written verdict with its reason: unreachable path, diagnostics, boot-only, capacity, or already measured with a citation. That is what makes the register current without measuring 700 boots, and it stops the next session re-asking the same question.

## The trap this avoids

A register that reports "70 unmeasured settings" reads like a 70-arm campaign. In practice most are other families' names, diagnostics or boot plumbing, and the true candidate set is small. Measure the list's composition before budgeting for it.
