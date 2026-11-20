#!/usr/bin/env bash
# finalstate.sh - the after-window state, recorded into out/FINAL.md on the box: production /health, the serve
# container, sparkDash on the Proxmox host, the GPU lock holders, and the box's free space.
set -u
cd "$HOME/work/KnobTest" || exit 1
OUT=out/FINAL.md
{
  echo "# Final state $(date -Is)"
  echo
  echo "- production /health: $(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8888/health)"
  echo "- https://127.0.0.1:8888/v1/models: $(curl -s --max-time 5 http://127.0.0.1:8888/v1/models | head -c 120)"
  echo "- container: $(docker ps --format '{{.Names}} {{.Image}} {{.Status}}' | tr '\n' ';')"
  echo "- gpu lock holders: $(pgrep -af '[f]lock .*gpu.lock' | tr '\n' ';')"
  echo "- sparkDash (from the laptop step): see RESULT.md"
  echo "- images: $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -c .) images; knob image: $(docker image inspect -f '{{.Id}}' tensorfold-qwen38:knob-m-1ece6e6d 2>/dev/null || echo absent)"
  echo "- free: $(df -h "$HOME" | tail -1)"
} > "$OUT"
cat "$OUT"
