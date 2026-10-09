#!/usr/bin/env bash
# prosefirst.sh: let the two prose lanes' queued holds take the GPU lock next. Every other waiting flock is stopped
# (SIGSTOP; nothing is lost); once the prose-glm hold has started (or after 3 h), all stopped waiters are continued.
# Log ~/work/merge/prosefirst.log.
set -uo pipefail
exec >> ~/work/merge/prosefirst.log 2>&1
L=~/work/gpu.lock
echo "== $(date -Is) start"
holder=$(lsof -F pl "$L" 2>/dev/null | awk '/^p/{p=substr($0,2)} /^l[WwRr]/{print p}' | head -1)
stopped=()
for p in $(lsof -t "$L" 2>/dev/null); do
  [[ "$p" == "$holder" ]] && continue
  [[ "$(cat /proc/$p/comm 2>/dev/null)" == flock ]] || continue
  tr '\0' ' ' < /proc/$p/cmdline | grep -q "lanes/prose\|prose-glm\|prose-opus" && continue
  [[ "$(readlink /proc/$p/cwd)" == *lanes/prose* ]] && continue
  kill -STOP "$p" && stopped+=("$p")
done
echo "holder $holder; stopped: ${stopped[*]}"
for i in $(seq 360); do
  pgrep -f "lanes/prose-glm.*hold1.sh|^bash hold1.sh" >/dev/null && \
    [[ "$(lsof -F pl "$L" 2>/dev/null | awk '/^p/{p=substr($0,2)} /^l[WwRr]/{print p}' | head -1)" != "$holder" ]] && \
    pgrep -af "bash hold1.sh" | grep -q . && \
    [[ -n "$(lsof -F pl "$L" | awk '/^p/{p=substr($0,2)} /^l[WwRr]/{print p}' | xargs -r -I{} readlink /proc/{}/cwd | grep prose-glm)" ]] && break
  sleep 30
done
for p in "${stopped[@]}"; do kill -CONT "$p" 2>/dev/null; done
echo "== $(date -Is) continued: ${stopped[*]}"
