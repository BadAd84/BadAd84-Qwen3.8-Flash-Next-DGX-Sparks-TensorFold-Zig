#!/usr/bin/env bash
# mac.sh REF|DIR NAME (spark6, ~/work/lanes/tfevict): compile the Metal engines' test module and the Flash Next reuse
# tool for aarch64-macos with an xcrun stub and no framework links (no SDK here): every semantic error in macOS-only
# Zig shows up, the final link cannot succeed. Log e/NAME.mac.log; prints the compiler's source errors.
set -uo pipefail
L=$HOME/work/lanes/tfevict
cd "$L" || exit 1
source ~/qwen-zig/scripts/config.sh
M=$L/e/$2-mac
docker run --rm --network none -v "$L/e:/e" --entrypoint rm "$BASE_IMAGE" -rf "/e/$2-mac" 2>/dev/null
mkdir -p "$M" || exit 3
if [ -d "$1" ]; then tar -C "$1" --exclude=.git --exclude=zig-out --exclude=.zig-cache -cf - . | tar -x -C "$M" || exit 3
else git -C "$L/tf" archive "$1" | tar -x -C "$M" || exit 3; fi
sed -i '/linkFramework("\(Metal\|Foundation\|IOSurface\)"/d; /linkSystemLibrary("objc"/d' "$M/build.zig"
docker run --rm --network none -v "$M:/tf" -v "$HOME/work/lanes/w2-fable/zig-toolchain:/opt/zig:ro" -v "$L/zcache:/root/.cache/zig" \
  -v "$L/xcrun:/usr/local/bin/xcrun:ro" -w /tf "$BASE_IMAGE" \
  bash -c "/opt/zig/zig build native test-native tf-flashnext-reuse -Dtarget=aarch64-macos -Doptimize=debug" > "$L/e/$2.mac.log" 2>&1
echo "$2 mac exit $?"
grep -aE "\.zig:[0-9]+:[0-9]+: error" "$L/e/$2.mac.log" | sort -u | head -40
grep -aE "undefined symbol" "$L/e/$2.mac.log" | sort -u | wc -l | sed 's/^/undefined symbols (no SDK, expected): /'
