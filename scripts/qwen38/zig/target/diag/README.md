# Diagnostic patch: where a decode round goes

`round-and-kernel-logs.patch` applies on the accepted rung of `patches/1.2.6` (the series through the draft head
lever; cut against the tree `mkrung.sh 0021` makes). It is a measuring instrument and is never part of a served
image.

- `TF_FLASHNEXT_ROUND_LOG=1`: every 64 rounds, the wall time a round of the lane backend's three calls (verify,
  keep, draft), of the parts inside verify (the forward, split for a graph window into the host's staging and the
  graph, and the draws) and inside draft (the absorb pass, the picks, the chain passes), and the host's wait between
  calls. Each part drains the stream when it ends, so the served tok/s under the log is not a speed result.
- `TF_CUDA_KERNEL_LOG=1` with `TF_FLASHNEXT_WINDOW_GRAPH=0`: every launch is waited for and its time booked to its
  kernel; the table (largest first) prints with each round log line. It needs the graphs off because a launch being
  captured into a graph cannot be waited for.

`kprof.sh` builds the image and runs the three boots (as served, graphs off, graphs off with the kernel log);
`profile_round.sh` runs any image that carries the patch.
