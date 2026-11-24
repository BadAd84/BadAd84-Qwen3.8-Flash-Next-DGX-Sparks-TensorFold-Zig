---
name: diagnose-gb10-tensorfold-memory-drain
description: "Diagnose a slow memory drain / OOM on a GB10 (DGX Spark) TensorFold serve: per-node sampling, torch.cuda.memory_stats via a /cuda endpoint, eliminating layers by config A/B, and the two root causes already found"
---

# Diagnosing a memory drain on a GB10 TensorFold serve

GB10 is unified memory (123 GiB shared by CPU+GPU), so ordinary Linux accounting misleads. Work in this order.

## 1. Facts before theories: who is actually low?

Sample **every node**, not just rank 0:

```bash
for n in 11 12 13; do ssh adam@192.168.99.$n 'printf "%s " $(hostname); free -m | awk "NR==2{printf \"avail %.1f GiB\", \$7/1024}"'; done
```

An uneven drain (e.g. rank 0 at 4 GiB while workers hold 14+) means the problem is **per-rank data
placement**, not a global leak. That single observation points at the KV/latent cache layout.

## 2. What is NOT evidence on GB10

- **Process RSS / smaps**: device allocations are invisible. Measured: the serve's smaps total was
  7.6 GiB while the process owned ~90 GiB of device memory. "RSS flat" never exonerates a device leak.
- **`nvidia-smi --query-gpu=memory.used`**: reports N/A on GB10. `nvidia-smi -q -d MEMORY` likewise.
- **MemAvailable at 1 Hz**: a sub-second allocation burst can hit the wall between samples. A trace
  showing "never below 11 GiB" can coexist with a real kernel `oom-kill`. Trust dmesg for the OOM,
  MemAvailable only for trends.

## 3. Name the growth with torch's own accounting

Add a read-only route to the image (patch `cuda/http.py`, build with the knobs-style Dockerfile):

```python
elif self.path.rstrip("/") in ("/cuda", "/v1/cuda"):
    import torch
    _s = torch.cuda.memory_stats()
    self._json(200, {"allocated_mib": _s.get("allocated_bytes.all.current", 0) >> 20,
                     "reserved_mib": _s.get("reserved_bytes.all.current", 0) >> 20,
                     "active_segments": _s.get("segment.all.current", 0),
                     "live_blocks": _s.get("allocation.all.current", 0),
                     "alloc_count": _s.get("allocation.all.allocated", 0),
                     "free_count": _s.get("allocation.all.freed", 0)})
```

Then drive the workload that drains it and read the endpoint before/after:

| allocated | reserved | verdict |
|---|---|---|
| grows | grows with it | live-tensor leak (find the owning structure) |
| flat | **grows** | **caching-allocator fragmentation** - fix with `expandable_segments:True` |
| both flat, avail still falls | - | driver/kernel-side (check Slab/Unevictable/PageTables in /proc/meminfo) |

## 4. The workload matters more than the volume

Fixed-shape probes never reproduce it. Use **concurrent growing conversations**
(`chainturn.py`, 4 in parallel, ~23k tokens appended a turn) - that is every real agent workload,
and it is what exposed both real bugs.

## 5. The two root causes already found on this fleet

1. **Kept-state bytes uncapped** - the entry cap (`TF_GLM_CACHE_ENTRIES`) bounds the COUNT; each state
   owns tensors outside the pool (DFlash2 window copies, hundreds of MiB for long conversations).
   Fix: `TF_GLM_KEPT_BYTES_GIB=8`. Symptom: `kept_bytes` climbing to tens of GiB, no fragmentation.
2. **CUDA allocator fragmentation** - reserved grew ~1.2 GiB per 3 turns while allocated stayed flat,
   until the node OOM'ed (victim held 428 GB of segment address space) or the serve wedged with
   kernels stalled in `forward.mm` (faulthandler `Timeout (0:05:00)`), which no idle-gated watchdog can
   restart. Fix: `_set_allocator_settings("expandable_segments:True")` before the first allocation when
   `--parallel > 1` (the recipe's qwen engines already do this; glm5_next did not).

## 6. Elimination order that worked

spill tier off (A/B) -> pure-torch churn loop (exonerates the driver) -> 300 fixed-shape requests
(exonerates per-request paths) -> 4 concurrent growing conversations (reproduces) -> /cuda counters
(names it) -> config flag (fixes it) -> same probe again (proves it).

## 7. Operating traps

- `restart_when_idle.sh` gives up after 30 min with no idle window; agents keep a busy serve busy
  forever. A controlled restart is often better than waiting.
- The system unit `glm-watchdog-system.service` will race a manual restart: `sudo systemctl stop` it
  (needs the forwarded agent), `docker rm -f` all ranks, start, then re-enable.
- A worker-only crash looks like "rank 0 is fine" at first glance: always read the **worker** rank
  logs (`~/.cache/tensorfold-glml53/logs/*rank1*.log.gz` on spark2), not just rank 0's.
- Our own lane patches can be incompatible with an upstream flag: enabling `TF_GLM_KV_SHARD` crashed
  the workers in `kernel_warm.py` (our WarmAll patch) with `'NoneType' object has no attribute 'shape'`
  because under sharding a rank owns only its part and the latent cache slot is `None`. Fix pattern:
  take the first non-None slot and return early when there is none.
