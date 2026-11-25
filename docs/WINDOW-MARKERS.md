# Window markers: who writes what

A watcher that waits for a marker a brief names rather than one the driver writes can idle for the whole
run and report nothing. That happened here: a watcher waited for `WINDOW-DONE` while the confirm driver
wrote `WINDOW3-DONE`, and it sat its full loop for nothing.

This table is read from each driver's own script on the box (`grep -hoE 'log "[A-Z0-9-]+' <driver>.sh`),
which is the only authoritative source. A brief that says "wait for X" must quote X from here or from the
driver, never from memory.

## Completion markers, per driver

| driver (box path) | completion marker(s) it writes | notes |
|---|---|---|
| `~/work/parity/window.sh` (the r5dev40 against production screen) | `RUN-DONE` | also writes `SCORE1`, `SCORE2`, `RERUN-OPEN`, per-cell `CELL-DONE`/`CELL-FAILED` |
| `~/work/parity2/window.sh` (the confirm pass) | `RUN-DONE`, `WINDOW-DONE` | |
| `~/work/parity2/window3.sh` (the A1/A3 confirm) | `RUN3-DONE`, `WINDOW3-DONE` | the number in the name is the window's, not a version |
| `~/work/parityid/window.sh` (the divergence window) | `RUN-DONE` | also `REPORT1`, `REPORT2`, `REPORT3`, `SKIP`, `DIST` |
| `~/work/kvdtype/window.sh` (the KV dtype arm) | `RUN-DONE` | also `DTYPE`, `ARGV`, `CELLS`, `SKIP` |

Every one of them also writes `RESTORED` on a clean restore and `EXIT-DONE` on exit, and every one writes
`BOOT`, `PLAN`, `PROBE`, `CELL-DONE`, `CELL-FAILED`, `RESOURCES-LOW`, `RESOURCES-TIMEOUT` and `STOPPED`
in the same spelling. `RESTORE` and `RESTORED` are separate lines: the first starts the restore, the
second is its proof.

## The rule this table exists for

Wait for the driver's own word. If the driver file is not readable, wait for `RESTORED` or for the lock
to be free plus `/health` 200, both of which every driver writes or leaves behind, and never for a name
carried in a brief. A watcher that outlives its window should also be written to exit on the marker it
finds rather than on a fixed loop count, and to log the line it matched, so a wrong marker shows up as an
expired loop with no `SYNCED`/`DONE` line rather than as silence.

## Markers that are NOT window markers

`gpu.lock` presence means a holder or a waiter, not a run in progress: `pgrep -af 'flock .*gpu.lock'`
returning one line is a waiter whose predecessor has gone. The engine's own boot lines (`information: ...`)
and the recipe's banner (`Window ... at once ...`) are not driver markers and are not parsed by anything.
