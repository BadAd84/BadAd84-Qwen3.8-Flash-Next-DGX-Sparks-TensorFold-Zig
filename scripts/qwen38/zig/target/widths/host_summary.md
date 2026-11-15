# Widths step host gates on the final head (5cc8b6a) and main (41a72fd257), Ubuntu 24.04 x86_64 container, Zig 0.17.0, -j6 --maxrss 6000000000

## dockersteps.sh
SETUP zig 0.17.0 base.tar 82598596da352ed2 patch 44dc6585ccad2f13
STEP base -Dfixed-cpu test-rows-startup-scale --test-timeout 20m rc 0 Build Summary: 3/3 steps succeeded; 7/7 tests passed
STEP base -Dfixed-cpu test-dsv41-device-host --test-timeout 20m rc 0 Build Summary: 6/6 steps succeeded; 223/223 tests passed
STEP head -Dfixed-cpu test-host --test-timeout 20m rc 1 Build Summary: 2061/2065 steps succeeded (1 failed); 19160/19300 tests passed (140 skipped)
STEP head -Dfixed-cpu test-golden rc 0 Build Summary: 5/5 steps succeeded
STEP head -Dfixed-cpu test-kernel-contract rc 0 Build Summary: 32/32 steps succeeded; 205/205 tests passed
STEP head -Dfixed-cpu fuzz-cortheon rc 0 Build Summary: 3/3 steps succeeded; 22/22 tests passed
STEP head -Dfixed-cpu test --test-timeout 10m rc 0 Build Summary: 690/690 steps succeeded; 397/410 tests passed (13 skipped)
STEP head test-cuda-host rc 0 Build Summary: 408/408 steps succeeded; 6729/6769 tests passed (40 skipped)
STEP head test-environment-host rc 0 Build Summary: 3/3 steps succeeded
MUTANT default-only rc 1 zig/src/families/flashnext/cuda_widths.zig:90:54: error: index 1 outside array of length 1 zig/src/families/flashnext/cuda_widths.zig:99:69: error: index 1 outside array of length 1 
MUTANT mlx-any rc 1 error: 'cuda_config.test.a top-5 config with a 1280-wide shared expert selects that shape, and the MLX path refuses it by name' terminated with signal ABRT with stderr: 
MUTANT scratch-const rc 1 error: 'cuda_widths.test.the scratch is sized by the shape: a wider shared expert's three buffers, fewer slots' pairs' failed: 

## dockrest.sh
SETUP zig 0.17.0 base.tar 82598596da352ed2 patch 44dc6585ccad2f13
STEP base -Dfixed-cpu test-release-directory-host rc 0 release privacy: refused leak.bin (PrivateBuildPath) Build Summary: 6/6 steps succeeded 
STEP head -Dfixed-cpu test-release-directory-host rc 0 release privacy: refused leak.bin (PrivateBuildPath) Build Summary: 6/6 steps succeeded 
MUTANT mtp-any rc 1 error: 'cuda_widths.test.the MTP layer routes at the main layers' top-k with its own shared width, and another width is refused' failed: 
MUTANT captured-any rc 1 error: 'cuda_widths.test.a captured kernel set serves the default shape only' failed: 
MUTANT fixed-top10 rc 1 error: 'cuda_config.test.a top-5 config with a 1280-wide shared expert selects that shape, and the MLX path refuses it by name' failed: error: 'cuda_widths.test.a width outside the supported list is refused by its field's name' failed: error: 'cuda_widths.test.the default shape is the constants' and a top-5 checkpoint selects a 1280-wide shared expert' terminated with signal ABRT with stderr: 

## dockhost.sh (test-host on both trees)
SETUP zig 0.17.0 base.tar 82598596da352ed2 patch 44dc6585ccad2f13
STEP base -Dfixed-cpu test-host rc 1 Build Summary: 2061/2065 steps succeeded (1 failed); 19145/19285 tests passed (140 skipped)
STEP head -Dfixed-cpu test-host rc 1 Build Summary: 2061/2065 steps succeeded (1 failed); 19160/19300 tests passed (140 skipped)
- base failed step: |  +- run python3 failure (FileNotFoundError: [Errno 2] No such file or directory: 'cc')
- head failed step: |  +- run python3 failure (FileNotFoundError: [Errno 2] No such file or directory: 'cc')

## dockvideo.sh (the failed step with gcc installed)
SETUP zig 0.17.0 cc cc (Ubuntu 13.3.0-6ubuntu2~24.04.1) 13.3.0 base.tar 82598596da352ed2 patch 44dc6585ccad2f13
STEP base -Dfixed-cpu test-video-layout-linux rc 0 Build Summary: 3/3 steps succeeded
STEP head -Dfixed-cpu test-video-layout-linux rc 0 Build Summary: 3/3 steps succeeded

The first container's head test-host also failed only test-video-layout-linux (run python3 failure, no cc).
