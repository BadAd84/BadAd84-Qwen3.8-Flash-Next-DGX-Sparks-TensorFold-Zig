---
name: measure-qwen-stock-vs-ours-parity-on-spark6
description: "Run a fresh-boot-per-cell stock-vs-ours (or lever A/B) matrix for the Qwen3.8 Flash Next Zig serve on spark6 at 1/2/4/6/8 streams with the par114 drivers, keeping the serve, the GPU lock and sparkDash honest."
---

# Qwen parity / lever A/B matrix on spark6 (par114 drivers)

Drivers (repo `qwen3.8-flash-next-dev/scripts/qwen38/zig/par114/`, box `~/work/lanes/par114/`): `arm.sh ARM C` boots one
cell bound to `127.0.0.1` at `PARALLEL=C`, records boot seconds, the `sequence memory` line, golden (`qf_harness.py golden`
vs `~/work/zab3/zgold-base-c1.json`, gating only for the `ours` arm), decode with every slot busy
(`~/work/lanes/tfmain/tfm_decode.py`, 3 passes, 512 greedy tokens; prompts ROTATE per pass and carry a nonce, so reply
shas are not comparable across passes), client TTFT (`~/work/bench/ttft.py`, cold 1k/8k/32k/120k, idle and C-1 load),
GPU temperature per window. `queue.sh` runs the ABBA order per level under `flock 9>~/work/gpu.lock`, stops the container
from an EXIT trap and touches `DONE`. `sum.py` prints the tables (boot/mem/golden/temp, stock-vs-ours decode with gains,
per-arm decode, TTFT by load). The 2026-11-07 run is the reference: ours (zmerge8-kfix, INT4) vs recipe v1.1.4 (NVFP4)
vs stock upstream 1.2.4 (NVFP4, bf16 KV) - recorded in `docs/FP4-PORT-AND-RETEST.md` 6.1.

## Arms and their settings (measured constraints)

- `ours`: `LOCK_HOLDER=0 HOST=127.0.0.1 PARALLEL=C ~/qwen6-start.sh` (the serve's own launcher; `LOCK_HOLDER=0` because the
  queue already holds the lock).
- `stock` (recipe v1.1.4, `~/work/lanes/rpr/recipe`): `PREPARE=0 CHECKPOINT=nvfp4 PARALLEL=C CONTEXT=$CTX HOST=127.0.0.1
  ./start.sh restart`. Its engine REFUSES `CHECKPOINT=int4` (`UnsupportedCheckpoint`), so the matrix is cross-quant and the
  table must say so; 6 and 8 streams do not fit at 262,144 tokens, use `CONTEXT=131072` there.
- `up124` (stock upstream, built by `~/work/merge/build-br.sh TAG git://192.168.99.16/up-pr/tf <FULL 40-char sha>`): the
  recipe's start.sh rejects the image until it carries `tf.kernels=embedded` - relabel with
  `echo "FROM tensorfold-qwen38:TAG" | docker build -q --label tf.kernels=embedded -t tensorfold-qwen38:TAG -`; its Flash
  Next family refuses `--kv-cache fp8`, so pass `KV_DTYPE=bf16`, `VISION=0`, `CONTEXT=131072`; 8 streams do not fit
  (32.9 GiB bf16 cache vs 31.4 free). A lever arm = same line with its own IMAGE.

## Order of operations (each measured to matter)

1. Stop sparkDash from the Windows side: `ssh root@proxmox.ots-int.net 'pct exec 111 -- systemctl stop sparkdash'`, and arm
   a DEAD-MAN on the proxmox host so a dead session cannot leave it off:
   `nohup bash -c "sleep 14400; pct exec 111 -- systemctl start sparkdash" >/dev/null 2>&1 </dev/null &`
   (never `pkill -f sparkdash-...` in the same command line: `pkill -f` self-matches the ssh command and kills the shell).
2. Stop the serve and free the lock: `(cd ~/qwen-zig && ./stop.sh)`; the holder (`qwen6-gpu-lock-holder`) now follows the
   container and exits by itself; if an old one lingers: `for p in $(pgrep -f qwen6-gpu-lock-holder | grep -vw $$); do kill $p; done`.
3. Verify ZERO `queue*.sh` / `arm.sh` / `start.sh restart` processes and no `qwen38-flash-next-tf` container before launching
   (`ps -eo pid,args | grep -E 'queue|arm\.sh|start\.sh' | grep -v grep`); two queues once ran at once and shared `runs/`.
4. Launch detached in its own short ssh: `(setsid nohup ./queue.sh > queue.log 2>&1 < /dev/null &)`; never run a multi-minute
   pipeline inline behind one `timeout`ed ssh (three died mid-flight: exit 124 and a WSL HCS timeout, leaving the box dark).
5. Watch with a bounded, separate command polling `test -f DONE` (the trap touches it on every exit path); on DONE: start
   sparkDash, restore the serve (`setsid nohup ~/qwen6-start.sh > ~/qwen6-boot.log 2>&1 < /dev/null &`), prove `/health`,
   `pgrep -f qwen6-gpu-lock-holder | wc -l` = 1.
6. `python3 sum.py` for the tables; quote the C-1 load TTFT row, the GPU temperature (ours ran 8-13 C hotter, ~1-2% in its
   disfavour), and the quant/context differences per arm.

## Traps

- Scripts edited by Windows Python `write_text` land as CRLF and fail `bash -n` with `in\r`; strip with `sed -i 's/\r$//'`
  before `bash -n` and deploy, and write with `newline="\n"`.
- Deploy with `ssh ... 'cat > file' < localfile` in its OWN ssh call; a `cat > file` inside a `( ... ) &` chain reads /dev/null.
- The first boot of a checkpoint on a new engine re-hashes it (~30 min); the recipe's `WAIT_TIMEOUT=1800` is shorter than
  that - pass 3600 or pre-warm the sidecars.
- `GOLD exit 1` on a different-engine or different-quant arm is informational (record its own six replies as that arm's
  reference); only `ours` gates on golden 6/6.
