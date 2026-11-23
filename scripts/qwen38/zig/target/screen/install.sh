#!/usr/bin/env bash
# install.sh [--disarm]: copy the tracked screen kit to spark6 and pin the committed dev.env's sha256.
#
# Run from the workstation at the top level of a Git Bash shell. It copies every kit file to
# $KS_BOX (default /home/adam/work/KnobScreen), copies the committed
# scripts/qwen38/zig/target/env/dev.env to $KS_BOX/refcommitted/dev.env, and writes its sha256 beside it.
# The driver reads that pin at start and refuses a copy whose sha differs, so the base of a window is
# provably the committed file rather than whatever sat in ref/.
#
# --disarm removes Main's GO file and stops any starter.sh on the box, then verifies both: a disarmed kit
# cannot start a window. It does not touch production, the GPU lock or an out/ directory.
set -eu
H=${KS_HOST:-adam@192.168.99.16}
BOX=${KS_BOX:-/home/adam/work/KnobScreen}
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../../.." && pwd)
ENV=$REPO/scripts/qwen38/zig/target/env/dev.env
export SSH_AUTH_SOCK=${SSH_AUTH_SOCK:-C:/Users/Adam/AppData/Local/gnupg/agent-gui/S.gpg-agent.ssh.cyg}
FILES=(driver.sh analyze.py check_env.py basefilter.py mkenv.py stub_cells.py rec.py result.py sens.py
       plan.tsv allow-extra.txt RULE.md starter.sh fetch.sh)
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=20 "$H")

if [ "${1:-}" = "--disarm" ]; then
  "${SSH[@]}" "rm -f '$BOX/GO'; pkill -f '[K]nobScreen/starter.sh' || true" < /dev/null
  go=$("${SSH[@]}" "[ -e '$BOX/GO' ] && echo present || echo absent" < /dev/null)
  n=$("${SSH[@]}" "pgrep -f '[K]nobScreen/starter.sh' | wc -l | tr -d ' '" < /dev/null)
  echo "DISARM GO=$go starter-processes=$n"
  [ "$go" = absent ] && [ "$n" = 0 ]
  exit $?
fi

[ -f "$ENV" ] || { echo "install: no committed env at $ENV"; exit 2; }
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/kit" "$tmp/envgate" "$tmp/refcommitted"
for f in "${FILES[@]}"; do cp "$HERE/$f" "$tmp/kit/$f"; done
cp "$HERE/../env/check-env-coverage.py" "$HERE/../env/check-env-coverage-selftest.sh" "$tmp/envgate/"
cp "$ENV" "$tmp/refcommitted/dev.env"
ref_sha=$(sha256sum "$tmp/refcommitted/dev.env" | cut -d' ' -f1)
printf '%s  dev.env\n' "$ref_sha" > "$tmp/refcommitted/dev.env.sha256"
tar -C "$tmp" -czf "$tmp/kit.tgz" kit envgate refcommitted
"${SSH[@]}" "mkdir -p '$BOX'" < /dev/null
scp -o BatchMode=yes -o ConnectTimeout=20 "$tmp/kit.tgz" "$H:$BOX/kit.tgz" < /dev/null
"${SSH[@]}" "cd '$BOX' && tar -xzf kit.tgz && rm kit.tgz && cp kit/* . && rm -rf kit && chmod +x driver.sh '$BOX/envgate/check-env-coverage-selftest.sh'" < /dev/null
box_driver=$("${SSH[@]}" "sha256sum '$BOX/driver.sh' | cut -d' ' -f1" < /dev/null)
box_ref=$("${SSH[@]}" "sha256sum '$BOX/refcommitted/dev.env' | cut -d' ' -f1" < /dev/null)
here_driver=$(sha256sum "$HERE/driver.sh" | cut -d' ' -f1)
[ "$box_driver" = "$here_driver" ] || { echo "install: driver sha mismatch box $box_driver here $here_driver"; exit 3; }
[ "$box_ref" = "$ref_sha" ] || { echo "install: ref sha mismatch box $box_ref here $ref_sha"; exit 3; }
echo "INSTALL-OK driver=$box_driver ref=$box_ref"
