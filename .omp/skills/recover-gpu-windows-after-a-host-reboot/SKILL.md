---
name: recover-gpu-windows-after-a-host-reboot
description: "Use when a shared GPU box reboots or power-cycles under running windows: confirm what recovered by itself, find what died, requeue in priority order, and gate self-starting lanes on a marker instead of a free lock."
---

# Recover GPU windows after a host reboot

A reboot kills every lane at once: flock holders disappear, in-flight build containers die, and no marker the dead lanes would have written exists. Recovery is three checks and one ordering decision.

## 1. Establish what the box did and what came back

- `uptime -s` gives the boot instant; `uptime` shows the age. Nothing about the pre-reboot state is trustworthy from memory.
- Production may have a restart policy and be back on its own. Read the container's image, status and start time (`docker inspect NAME --format '{{.Config.Image}} {{.State.Status}} {{.State.StartedAt}}'`), compare the image id to the pinned one, and poll `/health` until 200 (measured on spark6: about 70 s after StartedAt). Only manually restore when the container is absent or on the wrong image.
- The GPU lock file will exist with no holder; `flock` locks die with their process, so the file is not a signal of anything.

## 2. Identify what died, by name

For each window know its three artefacts: the lock waiter, the build container or serve it started, and the marker it would have written. A lane that reports "no container, no waiter, marker absent" has proven its window did not run; a run log holding only selftest marks is the same proof. Nothing of a lane's committed work is lost by a reboot; only in-flight state is.

## 3. Requeue in priority order, and make arrival order do the ordering

Rank by who the deliverable answers: an external maintainer request first, then a correctness gate that other windows depend on, then internal speed screens, then long confirmatory runs. Where lanes take a plain `flock`, the first dispatched requeue is the first in the queue; dispatch in that order and say the order in each message. A short gating window (a boot proof plus a fast verdict) intentionally runs ahead of long work and releases the lock early.

## 4. Gate self-starting lanes on a marker, not on a free lock

A lane armed to poll for a condition should require the marker the higher-priority receipt creates plus its own gate (for example `FAST-VERDICT` CLEAN and `~/work/<lane>/GO`). An absent marker means the condition has not happened; it never means pass. A lane that decides not to take a free lock because its gate is missing is behaving correctly.

## 5. Tell every requeued lane to re-verify staged inputs

A reboot can leave a partial build cache or a half-written staged tree. The requeue message requires a fresh sha256 check both ways before the first build, and names the head it must build.

## What to record

The boot instant, the production image and id plus the health time, which lanes lost what, the order chosen and the markers that now enforce it. That record is what stops the next session from re-deriving the queue.
