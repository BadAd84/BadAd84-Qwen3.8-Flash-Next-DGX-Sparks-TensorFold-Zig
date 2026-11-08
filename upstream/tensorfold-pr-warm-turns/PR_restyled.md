Title:
flashnext: Declare warm turns, so a reply's background pass can prefill the next turn's prompt

---------------------------
What this changes:
The lane core runs warm turns end to end:
Post a chat reply -> server/warm.zig prefills the next turn's
prompt in the background,
-> lane_host_warm.zig pre empts the pass at any chunk when real work arrives
The mechanism is there for any family that declares "warm_quiet";
until now only Nemotron did, and cuda_startup_phase.zig had hard coded Nemotrons quiet constant. So a flash next serve never warmed.
This change adds these 2 declarations to flash next CUDA family ("warm_quiet = 150ms",
"warm_opt_in =true") moves the quiet window the info.warm_quiet_ms instead of the hard
coded constant and reads TENSORFOLD_WARM_TURNS strictly: exactly "1"or "0" (or unset/empty) anything else refuses to start with the setting's name.
Off by default, so a default boot is unchanged.

---------------------------
Why:
You know what the next turns prompt is the minute the previous reply ends. Prefilling it in the background moves almost all of the next turn's prefill off the critical path: on one gB10 (nvfp4 checkpoint, bf16 kv, 131072 token windows) I saw nextturn time to first token go down 38-45%at 1 and 2 stream with the second turns prompt fully cached by the time it arrives (measured rows: 100782 of 100802 at 100k)

---------------------------
The trade, measured:
A fresh prompt sent while the warm pass held the GPU waiting for it. At a 0.2s pause after the reply cold 8k prompts time to first token went up by 8.6%at 1 stream, and 6.3%at 2 (at 1 and 3 second pauses its essentially noise -  the 150ms quiet window plus the prefill fits inside a second). Its turned off by default though, so the trade is opt in per serve.

---------------------------
Checks on this head:
- Head commit: ed50016cdf on upstream 267c5af6a - both arms built from that tip.
- Lean checker, each tree with its own copy: 116 problems on base(head), 0 new.
- Tests: zig build test --summary all (w/ no GPU and no network) - both build the same steps with the exact same failing test list (one listener test that needs a netowrk, 2 drama_voice_tool cleanup tests that expect error.AccessDenied as root). Equal per test passes
- Boxes it reaches: 1x nvidia gB10 (DGX Spark class), cuda. Not run:
      Metal|HIP|XPU host tests (this box is CUDA only) and any GPU kernel contract (no kernel changes).
- Exactness: golden 6/6 identical on every cell (ports replies equal to stocks own replies, 24 boots across 6 cells), and every copy/rewrite/edit reply hash the same between the arms.
- Decode/idle/loaded TTFT and the copy/rewrite/edit workloads are equal across all arms within the boot spread - the memory line in the boot log is unchanged (nvidia-smi not available on gB10, so its just the allocators own line).
- Boot cost: 0-4s on the warm on arm.

---------------------------
Measurement:
1x fresh boot per cell, abba order. Medians over 2 boots a cell at 1 stream and 2
nextturn time to first token from the client at temp 0 (the trade cell sends a fresh 8k prompt at a fixed pause after each reply). Raw cells and the summariser on the measurement box, so these numbers are medians the tool printed.
---------------------------
Checklist:
- [X] Title/description matches head commit/measurement
- [X] Setting is strict - an unknown value refuses to start with its name and unset is exactly today's behaviour
- [X] Comments/docstrings one line. No measurements/histories in the source
- [X] No personal data, machine names or internal hosts/paths on the diff or its commits
- [X] Drafted output == "draft": false and Concurrent == solo on both arms
- [X] No precision traded for speed - warm pass prefills prompts and changes no arithmetic.