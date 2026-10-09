#!/usr/bin/env bash
# jump.sh: run mverify.sh next on the GPU lock without losing anyone's queued hold. Waiting flock processes are
# stopped (SIGSTOP) so they cannot take the lock when the current holder releases; ours waits; once ours holds the
# lock, every stopped waiter is continued (SIGCONT) and simply waits for us. Log ~/work/merge/jump.log.
set -uo pipefail
exec >> ~/work/merge/jump.log 2>&1
L=~/work/gpu.lock
echo "== $(date -Is) jump start"
holder=$(lsof -F pl "$L" 2>/dev/null | awk '/^p/{p=substr($0,2)} /^l[WwRr]/{print p}' | head -1)
echo "holder: ${holder:-none}"
stopped=()
for p in $(lsof -t "$L" 2>/dev/null); do
  [[ "$p" == "$holder" ]] && continue
  [[ "$(cat /proc/$p/comm 2>/dev/null)" == flock ]] || continue
  kill -STOP "$p" && stopped+=("$p")
done
echo "stopped waiters: ${stopped[*]}"
printf '%s\n' "${stopped[@]}" > ~/work/merge/stopped.pids
flock "$L" bash -c '
  echo "== $(date -Is) lock taken by merge verify3"
  for p in $(cat ~/work/merge/stopped.pids); do kill -CONT "$p" 2>/dev/null; done
  echo "continued: $(tr "\n" " " < ~/work/merge/stopped.pids)"
  bash ~/work/merge/mverify3.sh > ~/work/merge/mverify3.log 2>&1
  echo "== $(date -Is) merge verify3 done, releasing"
'
