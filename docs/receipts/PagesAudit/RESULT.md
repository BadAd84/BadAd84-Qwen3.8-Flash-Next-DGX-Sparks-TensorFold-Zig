# PagesAudit: the paged fp8 KV path at the real long window on the served r5 tree

Status: **measured and restored.** One window on spark6 under `~/work/gpu.lock` (acquired 22:32:42Z; its twelve
cell boots ran 22:49:44Z to 23:25:50Z per the cell `boot_time.txt` files and the markers), plus one single-cell
re-run at 23:37:14-23:41:35Z for the resume cell whose first pass ran before the resume tool's keep-alive fix.
Final markers in `~/work/PagesAudit/out/marks/`: `RUN-DONE`, `SUMMARY-OK`, `RESTORED`, `PROD-IMAGE-OK`,
`PROD-ENV-EQUAL`, and the twelve `CELL-*` markers. Artifacts are fetched under `work/PagesAudit/out.fetched/`
(`out/cells/`, `out/marks/`, `out/SUMMARY.md`, `out/run.log`, `out/RESTORED`, `out/prod-env-*.txt`,
`out/supplement-plan.txt`). The driver delivered as `work/PagesAudit/window.sh` is sha256
`0acdd7a76c6bca2b9f9c236158fa7e6b4c4ba3bd36c9de58b7c15bbaa0a3ed34`; the main run executed `0a4069f0...` and the
single-cell re-run `e3bd6146...` (fetched as `out.fetched/window.sh`), whose only difference from the delivered file
is the post-run log-append fix below. The tools are pinned in `out.fetched/tools/MANIFEST.sha256`.

Provenance note, measured: the main run executed `0a4069f0...` (checked on the box while it ran), and its
`out/run.log` line was later truncated by the re-run's launch (`: > run.log` in the queue block). The fetched log
therefore holds the re-run's `SCRIPT e3bd6146...` lines, and the main run's timeline above is the markers' and
cells' own file times. The driver now appends to the log instead of truncating it; the inter-version differences
are the stats-poller pipe fix, the holder-spawn removal, the action-preserving re-exec and this append.

## The arms and how they were run

On `tensorfold-qwen38:qr-a-r5-1ece6e6db` (`sha256:001fc6ff...`, the served r5 FP4 tree), through the rpr recipe's
`start.sh`, with `scripts/qwen38/zig/target/env/dev.env` at sha256 `0152877747...` sourced as the launcher takes it
(`set -a; . dev.env; set +a`), fp8 KV, the NVIDIA FP4 checkpoint, vision off (the dev serve's mode), a 262,144-token
window, `--dashboard` so `/stats` answers:

| level | pages on | pages off |
|---|---|---|
| 6 | `on-c6-cold` (`--prompt-cache-gib 0`), `on-c6-resume` (`--prompt-cache-gib 6`) | `off-c6-cold`, `off-c6-resume` |
| 8 | `on-c8-cold`, `on-c8-resume` | `off-c8-cold`, `off-c8-resume` |
| 4 cold / 3 resume (supplement) | `on-c4-cold`, `on-c3-resume` | `off-c4-cold`, `off-c3-resume` |

Pages on is `TF_FLASHNEXT_KV_PAGES=4096`; pages off is the name **absent** from the booted file and the container
(`envproof.py` on every cell: 108 of 108 forwardable names equal and the file's two unsets absent on the on arm,
107 of 107 on the derived off arm, and `require-absent` for the page name). Every boot's `arm.txt` also gates the
image id, the banner (`nvidia/Qwen3.8-Flash-Next-FP4-Local.*6 at once.*262144-token window.*fp8 KV.*vision off`),
`--prompt-cache-gib` (0 or 6), `--dashboard` and `--kv-cache fp8` in the container's own `.Config.Cmd`. Every cell
is a fresh boot; arms interleave within each level and mode, and the modes run in opposite order (on/off cold, then
off/on resume). A refusal is recorded with the engine's own line and never retried into another shape.

The supplement was not assumed: the ON C6 plan reports `own 5.27 GiB` and `left 22.4 GiB`, so the driver derived
`max_cold = floor(22.4/5.27) = 4` and `max_resume = 3` (the largest level whose `left - L*own` keeps the 6 GiB cache
ask), wrote `out/supplement-plan.txt`, and booted exactly those (`off-c4-cold`, `on-c4-cold`, `off-c3-resume`,
`on-c3-resume`). The engine's own refusal advice at 6 and 8 is `serve --parallel 4`, the same derivation.

## 1. Admission: the page pool changes it at 6 and 8

One fresh boot a cell; `/health` and the plan line are the system's own.

| level, mode | pages on | pages off |
|---|---|---|
| 6 cold | **admitted** (rc 0, 52 s, `/health` 200): `6 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 5 more taking 238 pages of 4096 rows (17.14 GiB) as they need them, 0 MiB fixed each, of 22.4 GiB left after a 10.0 GiB reserve ... no prompt cache` | **refused** (rc 1, 52 s, `/health` 000): `--parallel 6 needs 31.60 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 22.42 GiB: serve --parallel 4, or lower --context` |
| 8 cold | **admitted** (rc 0, 52 s, `/health` 200): `8 streams at once, ... 7 more taking 238 pages of 4096 rows (17.14 GiB) ... of 22.4 GiB left ... no prompt cache` | **refused**: `--parallel 8 needs 42.14 GiB ... leaves 22.42 GiB: serve --parallel 4, or lower --context` |
| 6 resume | **admitted**: `5 more taking 154 pages of 4096 rows (11.09 GiB) ... a 3.1 GiB prompt cache` | **refused**: the same `31.60 ... leaves 22.44 GiB` line |
| 8 resume | **admitted**: `7 more taking 155 pages ... (11.16 GiB) ... a 3.1 GiB prompt cache` | **refused**: the same `42.14 ... leaves 22.44 GiB` line |
| 4 cold (supplement) | **admitted**: `3 more taking 225 pages of 4096 rows (16.20 GiB) ... no prompt cache` | **admitted**: `4 streams at once, 5.27 GiB each at a 262144-token window (fp8 caches) ... no prompt cache` |
| 3 resume (supplement) | **admitted**: `2 more taking 150 pages of 4096 rows (10.80 GiB) ... a 3.1 GiB prompt cache` | **admitted**: `3 streams at once, 5.27 GiB each ... a 6.0 GiB prompt cache` |

**The page pool changes admission on this image**: at the audited levels the unpaged shape needs 31.60 GiB (6) /
42.14 GiB (8) against a 22.42-22.44 GiB budget and is refused by name, while the paged shape admits both, eight
streams on 238 pages. It does not change admission at the largest unpaged-admissible level: 4 cold streams and 3
resume streams run both ways. The parenthetical "it should not" is therefore false for this env of record: the pool
is an enabler at 6 and 8, not a neutral rearrangement.

## 2. Cold TTFT, prompt cache off (client-measured, 3 reps, medians)

| cell | 32k | range | 128k | range | 128k prefill (server) | 128k server TTFT |
|---|---:|---|---:|---|---:|---:|
| on-c6-cold | 13.183 s | 13.138-13.471 | 56.340 s | 55.883-56.515 | 56.282 s | 56.337 s |
| on-c8-cold | 13.329 s | 13.259-13.435 | 56.606 s | 56.273-56.639 | 56.552 s | 56.603 s |
| on-c4-cold | 13.234 s | 13.231-13.448 | 56.569 s | 56.550-56.803 | 56.526 s | 56.567 s |
| off-c4-cold | 13.300 s | 13.205-13.476 | 56.621 s | 56.389-56.764 | 56.566 s | 56.618 s |
| off-c6/c8 | refused | | refused | | | |

On against off at C4 (the like-for-like level): **-0.5% at 32k and -0.1% at 128k, LEVEL**. The pool costs nothing
measurable on prefill; at 6 and 8 the comparison does not exist because the off arm does not admit. The cold 128k
TTFT is the prefill: 56.3-56.6 s on both arms, and the client-minus-server gap is 0.04-0.06 s (admit).

## 3. Decode at the level (2 passes a kind, 512 tokens a request, greedy)

| cell | kind | per-stream median | aggregate | tok/wall | tokens |
|---|---|---:|---:|---:|---:|
| on-c4-cold | prose | 26.64 s^-1 | 103.95 s^-1 | 94.9 | 3,943 |
| off-c4-cold | prose | 26.73 s^-1 | 104.15 s^-1 | 95.0 | 3,943 |
| on-c4-cold | code | 39.73 s^-1 | 157.35 s^-1 | 141.8 | 4,096 |
| off-c4-cold | code | 39.60 s^-1 | 157.95 s^-1 | 142.3 | 4,096 |
| on-c6-cold | prose | 23.22 s^-1 | 134.70 s^-1 | 120.4 | 5,975 |
| on-c6-cold | code | 33.90 s^-1 | 200.80 s^-1 | 180.0 | 6,144 |
| on-c8-cold | prose | 19.70 s^-1 | 153.60 s^-1 | 137.1 | 7,900 |
| on-c8-cold | code | 29.52 s^-1 | 230.90 s^-1 | 202.4 | 8,192 |

On against off at C4: **-0.2% prose and -0.4% code on the aggregate, LEVEL**, with identical rounds/drafted/accepted
per pass and **16 of 16 per-request reply shas identical between the arms** (`SUMMARY.md` section 9). At 6 and 8 the
paged arm is measured only against itself; the per-stream rate falls with concurrency (26.6 -> 23.2 -> 19.7 prose)
and the aggregate rises (104.0 -> 134.7 -> 153.6), as the same 512-token replies spread over more streams.

## 4. Resume: turn 2 of a kept conversation at 129k

`turn2.py`: A1 sends a fresh 129k conversation; A2 asks it again (the resume); T2 sends the appended second turn
`[P, R1, Q]`; A3 asks the base conversation again. A resumed prefix is reported by the server's own `cached` tokens.

| cell | A2 cached | A2 TTFT | T2 cached | T2 TTFT | A3 cached | verdict |
|---|---:|---:|---:|---:|---:|---|
| on-c6-resume | 129,241 | 0.158 s | 129,241 | 0.403 s | 0 | PASS (core), state not survived |
| on-c8-resume | 129,243 | 0.178 s | 129,243 | 0.353 s | 0 | PASS (core), state not survived |
| on-c3-resume | 129,243 | 0.176 s | 129,243 | 0.344 s | 0 | PASS (core), state not survived |
| off-c3-resume | 129,245 | 0.192 s | 129,245 | 0.341 s | 129,245 | PASS, state survived |
| off-c6/c8-resume | refused | | | | | |

- **The resume works on both arms and the token check passes**: A2's and T2's replies carry one text sha with A1's
  (greedy decode, resumed prefix), and the miss cost is the whole prefill - A1's fresh 129k took 56.8-57.5 s, and
  A3's miss at C6 re-prefilled in 57.0 s.
- **The appended turn resumes past the base prompt**: T2's cached prefix is 129,244 at C6, 7 tokens short of A1's
  129,251-token prompt (the generation suffix), so only the new tail was prefilled: 0.377 s against ~57 s cold.
- **The paged cache's 3.1 GiB store keeps one 129k state; the appended turn's own state displaces the base
  conversation, so A3 misses** (`prompt cache: 129286 tokens, resumed at 129241, kept 1; 2 states, 2548 MiB and 0
  MiB spare of 3166 MiB (evicted 2)` then `129248 tokens, resumed at 0; ... (evicted 4)`). At C3 the unpaged arm's
  printed 6.0 GiB cache keeps both, and A3 hits (129,245). On against off at C3: **T2 TTFT +0.9% and A2 cached equal,
  LEVEL**; the difference is state survival, not resume speed.
- The engine streams `: keepalive` comments during a silent 57 s prefill (`server/sse.zig:26-27`); the first pass of
  `on-c6-resume` counted them as errors and its verdict read FAIL. The tool now ignores SSE framing and separates the
  core resume (A2/T2) from state survival (A3); the cell was re-run under that version (`TURN2 ... verdict PASS`,
  `TURN2-SURVIVAL A3_cached 0 survived False`), and `on-c8-resume`/`on-c3-resume`/`off-c3-resume` ran under it.

## 5. Waits and counters the engine actually reports

- `/stats` (`--dashboard`): `waiting` was **0** in every cell (max `running` 6, 8, 4 at the cold levels and 1 at every resume cell); the
  snapshot's `prompt_cache` carries states/bytes/hits/misses and the prefill-reuse split.
- The serve's own `done` lines: every request's `queued=` was **0 to 0.146 s** (cold decode waves started
  simultaneously: 20 of 31, 28 of 39, 10 of 23, 11 of 23 requests queued, max 0.129-0.146 s; resume cells 0-1 at
  0.001 s), and `cached=` carries the resume hits.
- **No page or map counter exists to report**: the flashnext pool prints its plan and the `KV page groups` line at
  load (one page 73.75 MiB, 4,096 rows; 18.44 KiB a token; the state run 673.39 MiB on 10 pages, 8.7% padding; the
  snapshot 110.29 MiB on 2 pages) and no per-request page or map wait during the run. The waits it does expose are
  `/stats.waiting` and `done queued=`, both above. `/metrics` mirrors `requests_waiting`; it has no page gauge.

## 6. What the ~14 GiB claim would require, and what our plan reports

The audit's claim is a memory claim: that paging frees about 14 GiB at the real long window. A saving is only
measurable where the unpaged shape also admits. **On this image it does not at the audited levels**: the unpaged
requirement is 31.60 GiB (6 streams) and 42.14 GiB (8), against a 22.42-22.44 GiB budget, so those cells are
refusals by name and there is no admitted baseline to save 14 GiB against.

Where both arms admit (C4 cold), the paged plan reports 5.27 GiB own + 225 pages x 73.75 MiB = **21.47 GiB**, and
the unpaged plan reserves 4 x 5.27 = **21.08 GiB**: a 0.39 GiB difference, not 14. At 8 streams the paged plan
reports 5.27 + 17.14 = **22.41 GiB** against an unpaged requirement of **42.14 GiB** (a 19.73 GiB difference), and
at 6 it is **22.41 against 31.60** (9.19 GiB) - but in both the unpaged shape is refused, so those numbers price a
refusal, not a saving. The plan's own page count and GiB are what the engine prints: **238 pages / 17.14 GiB** at
both 6 and 8 cold, **154-155 pages / 11.09-11.16 GiB** at the resume shapes (one page of boot-to-boot budget
variation), and the 3.1 GiB prompt cache the 6 GiB ask yields in the paged split. The 14 GiB figure is not reproducible from this plan; the pool's measured value here is
**admission** (eight slots where four unpaged windows fit) at no measurable TTFT or decode cost where both arms ran.

## 7. Restore and the drift check

Production was restored from the EXIT trap with `~/qwen6-start-prod.sh` under the pinned image
`tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, and the restore was proved three times (main run 23:27:23Z, the
stop of the second launch 23:36:18Z, and the single-cell re-run 23:41:35Z):

- `/health` **200**; container image and id `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`
  `sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f` (`PROD-IMAGE-OK`);
- the drift gate on a fresh `docker inspect` (`check-prod-env.py --inspect`):
  `prod-env: 54 settings in prod.env (54 stated, 0 unset), 54 in the container, 54 equal, 0 problem(s)`
  (`PROD-ENV-EQUAL`), identical to the pre-window baseline line captured in the same window
  (`out.fetched/out/prod-env-before.txt` vs `prod-env-after.txt`).
- `~/INVENTORY.md` on spark6 carries the lane's entry (dir, tools, removal); the window builds no image and installs
  nothing.
