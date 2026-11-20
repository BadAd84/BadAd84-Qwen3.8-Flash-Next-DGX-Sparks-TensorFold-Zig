# KnobTest handoff (spark6)

State: an upstream-main image is being built and three GPU windows are queued, each from its own detached driver
under the same `~/work/gpu.lock` (FIFO). Everything is plan driven; nothing needs a decision.

## Markers

| file | meaning |
| --- | --- |
| `~/work/KnobTest/out/build.log` | `LOCK-ACQUIRED`, the docker build, `BUILD-DONE`, `BUILD-WRAPPER-EXIT` |
| `~/work/KnobTest/out/build.out` | the image's id, entrypoint and the `SOURCE`/`NVCC`/`ZIG`/`BUILD OK` lines |
| `~/work/KnobTest/out/w1/run.log` | window 1: `START`, `BOOT`, `PROBE`, `ARM-OK`, `ARM-FAILED`, `RESTORE`, `DONE` |
| `~/work/KnobTest/out/w1/RUN-DONE` | window 1 finished (its `production.txt` holds the /health code) |
| `~/work/KnobTest/out/w2/RUN-DONE`, `.../w3/RUN-DONE` | the same for windows 2 and 3 |
| `~/work/KnobTest/out/<window>/analysis/` | `cells.csv`, `ttft.csv`, `resume.csv`, `summary.json`, the markdown tables |

## What each window measures

- `w1`: base pair M1/M2 around `TF_FLASHNEXT_CHUNK=1536` (twice) and `TF_FLASHNEXT_READOUT_FUSED=1` (twice), passes
  A (decode + exactness, cache on, `--parallel 8`, 32,768 window) and B (cold TTFT 2k/8k/32k/64k, cache off,
  `--parallel 4`, 131,072 window, plus the cache-off fresh/drafts exactness).
- `w2`: base pair around `CHUNK=4096` (twice), `CHUNK=6144` (twice), `CHUNK_SOLO=3072` (twice, the "off" value on a
  `--parallel 8` server), and one pass A each for `TF_SHARED_PRICE_LOG=1`, `TENSORFOLD_DEVICE_CHECK=0`,
  `TENSORFOLD_UNIFIED_HOST_COUNTS=0`, `TENSORFOLD_MEMORY_RESERVE_GIB` unset.
- `w3`: base pair around `TF_CACHE_EVICT=decayed_resume` (pass D: the resume-pressure bench plus decode 1/2/4) and
  the one-stream solo chunk: `CHUNK_SOLO` unset (8,192 rows), 3,072 and 16,384 (pass P: cold TTFT and decode at one
  stream, cache off).

## The noise rule's rerun pass

After a window's analysis, a cell flagged `slower` gets one rerun in the same window:

```
python3 ~/work/KnobTest/scripts/analyze_knobs.py ~/work/KnobTest/out/w1 --base M1,M2 --write
python3 ~/work/KnobTest/scripts/rerun_plan.py ~/work/KnobTest/out/w1 --plan ~/work/KnobTest/plans/w1.tsv --window w1 --write
# plans/w1r.tsv then holds M1, the flagged treatments (each twice, same overrides) and M2
setsid nohup bash -c "cd $HOME/work/KnobTest; bash scripts/run_knobs2.sh w1r" > out/w1r.nohup 2>&1 < /dev/null &
```

The rerun plan is empty when nothing was flagged, and the analyzer re-run over `w1,w1r` merges the four runs a side.

## To finish by hand if a driver dies

1. `ssh adam@192.168.99.16`
2. `tail -20 ~/work/KnobTest/out/<window>/run.log` names the arm and the pass it died in.
3. Restore production if it is down:
   `( cd ~/work/lanes/rpr/recipe && ./stop.sh ); ( env LOCK_HOLDER=0 ~/qwen6-start-prod.sh </dev/null )`, then
   `curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8888/health` must print 200.
4. Re-run a window: `cd ~/work/KnobTest && setsid nohup bash scripts/run_knobs.sh <window> > out/<window>.nohup 2>&1 < /dev/null &`
   (it takes the lock itself; an arm whose directory already exists is redone).
5. Analyse: `python3 scripts/analyze_knobs.py out/<window> --base M1,M2 --write`.
6. Delete the scratch when the evidence is fetched: `rm -rf ~/work/KnobTest` (and its INVENTORY.md entry).
