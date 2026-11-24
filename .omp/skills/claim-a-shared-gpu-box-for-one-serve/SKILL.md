---
name: claim-a-shared-gpu-box-for-one-serve
description: User wants all queued GPU work stopped and one named serve left running on a shared box (e.g. spark6); preempt the benchmark queue and hold the serve.
---

# Claim a shared GPU box for one serve

When the owner says "stop whatever is queued and leave <model> up so I can use it", the box is
usually mid-A/B-campaign with window runners flock-waiting. Do NOT reason about the queue - preempt it.

## 1. Enumerate, then kill with bracket patterns

`pkill -f <pattern>` over ssh self-matches (the ssh argv contains the pattern) and kills its own
session - exit 255, empty output. ALWAYS bracket the first character:

```sh
ssh box 'pkill -9 -f "[w]indow_"; pkill -9 -f "[b]ringup_prod"; pkill -9 -f "[b]uild-br"'
```

Then verify, one query per concern:

```sh
pgrep -fa "[w]indow_|[r]etune|[b]ringup" | cut -c1-70 || echo CLEAN
pgrep -c -f "[b]uild-br|[z]ig build"
docker ps -a --format "{{.Names}} {{.Image}} {{.Status}}"
```

Kill watchers LAST but do kill them: a restore-watcher will re-start a serve you are trying to
control, and a `bringup` loop will re-run a launcher after you killed the window.

## 2. Check what the box's launcher actually is

Launchers are generation-split. Read the script's recipe path before trusting it: on spark6
`~/qwen6-start.sh` calls an fd3f43e recipe whose arg-check rejects `--kv-cache`, so it cannot restore
the zmerge8 image; `~/qwen6-start-prod.sh` (recipe @ 364f21a) is the production one. A wrong
generation fails the boot at the arg check, not at the model load.

## 3. Start detached, then prove health AND a real completion

`/health` 200 alone is not proof (the endpoint answers before the engine is warm and after a partial
boot). Send one small completion and check the reply text and `usage.completion_tokens`:

```sh
curl -s -m 5 .../health            # expect 200
# then a real chat completion with max_tokens ~120, reasoning_effort low
# expect non-empty content and plausible token count
```

## 4. Confirm the held state

Re-run the process enumeration and the container inspect (`image=`, `State.StartedAt`) in one pass.
Report: image id, start time, /health, the probe reply, and "queue empty".

## Traps

- The recipe's `stop.sh` stops AND REMOVES the container by name; a restore must recreate
  (`start.sh` does `docker run -d --name`), never `docker start`.
- A ghost flock (dead holder, live fd inherited by a child) blocks every waiter: `mv` the lock aside,
  `touch` a fresh one, kill stranded waiters.
- Never run `docker system prune` or label/ancestor-filtered `docker rm` on a shared box: the arm
  images share the production image's label.
