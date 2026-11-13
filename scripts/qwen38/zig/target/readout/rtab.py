#!/usr/bin/env python3
"""rtab.py ours|prod LOG - the decode window's dense projections, read-outs, shared expert and router, by tensor shape.

The decode window is the kernel log's last table (a trailing request closes it); its rounds are the server's `done`
lines between the table before it and it (expert_ids/ktab3.py's window when the log holds two tables; with the
read-outs on 12-bit copies the boot adds one). Each kernel
row is matched to the weight it reads by symbol and grid (grid = column blocks: N / 64, N / 32 for the half tiles,
N / 32 for the q12 down, N / 8 for the q12 up-mix), and its bytes a launch come from the checkpoints' tensor shapes
on one basis for both stacks: weights x bytes a weight of the format the kernel reads (MXFP8 1 + 1/32, block FP8
(FP8G) 1 + 4/64, BF16 2, the 12-bit copy 776/512: a block of 512 weights is 512 sign-mantissa bytes, 256 of 4-bit
exponents and 8 row exponents; escapes, under 0.1%, left out). Shapes (config.json and the safetensors headers of
both checkpoints, read by ~/work/target/ckpt_bytes.py): hidden 2560, GDN in_proj qkv 10240 + z 6144 + a 48 + b 48,
out_proj and o_proj [2560, 6144], q 12288 + k 512 + v 512 (+ the indexer's q-k 640 on ours, MXFP8; BF16 on
production's), read-out down [320 + 4 inject, 10240] and up [10240, 320] BF16, shared expert 640 wide on ours (MXFP8)
and 1280 on production's (FP8), router [512, 2560] BF16.
"""
import re
import sys

HEAD = re.compile(r"^kernel log: window ([\d.]+) ms wall, ([\d.]+) ms in kernels, (\d+) launches")
ROW = re.compile(r"^kernel log: ([\d.]+) ms (\d+) launches ([\d.]+) us each grid (\d+) (.*)$")
DONE = re.compile(r"done chatcmpl-\S+ .* rounds=(\d+)")

MX, G8, B16, Q12 = 1 + 1 / 32, 1 + 4 / 64, 2.0, 776 / 512
H = 2560


def ours_rules():
    q = "_ZN7tf_qmmf11qmmf_kernelILi{}ELi16ELi{}ELi1ELi4ELi4ELb{}ELb{}ELb0"
    r = [
        ("mixer", "GDN in_proj [16480, 2560] MXFP8", q.format(2, 64, 0, 0), 258, 16480 * H * MX),
        ("mixer", "out_proj, o_proj [2560, 6144] MXFP8, cluster", q.format(2, 64, 1, 1), 40, H * 6144 * MX),
        ("mixer", "q, k, v, indexer q-k [13952, 2560] MXFP8", q.format(2, 64, 0, 0), 218, 13952 * H * MX),
        ("shared expert", "gate, up [640, 2560] MXFP8 (two calls a layer)", q.format(2, 32, 0, 1), 20, 640 * H * MX),
        ("shared expert", "down [2560, 640] MXFP8", q.format(2, 32, 1, 0), 80, H * 640 * MX),
        ("read-outs", "down [324, 10240] BF16, verify and draft", q.format(4, 32, 1, 1), 11, 324 * 10240 * B16),
        ("read-outs", "up [10240, 320] BF16, verify and draft", q.format(4, 64, 0, 0), 160, 10240 * 320 * B16),
        ("read-outs", "down [324, 10240] 12-bit copy", q.format(5, 32, 1, 1), 11, 324 * 10240 * Q12),
        ("read-outs", "up [10240, 320] 12-bit copy", q.format(5, 64, 0, 0), 160, 10240 * 320 * Q12),
        ("drafter", "q, k, v, indexer [13952, 2560] BF16", q.format(4, 64, 0, 0), 218, 13952 * H * B16),
        ("drafter", "o_proj, fc and the like [2560, K] BF16, cluster", q.format(4, 64, 1, 1), 40, None),
        ("drafter", "shared gate, up [640, 2560] BF16", q.format(4, 32, 0, 1), 20, 640 * H * B16),
        ("drafter", "shared down [2560, 640] BF16", "tf_qmmf_shared16_half", 80, H * 640 * B16),
        ("router", "router [512, 2560] BF16", "tf_route_logits_few", None, 512 * H * B16),
    ]
    return r


def prod_rules():
    ld = "_ZN13tf_fn_qmmf_ld11qmmf_kernelILi3ELi16ELi64ELi1ELi4ELi4ELb0ELb0ELb{}"
    fq = "_ZN10tf_fn_qmmf11qmmf_kernelILi3ELi16ELi64ELi1ELi4ELi4ELb{}ELb{}ELb{}"
    return [
        ("mixer", "GDN in_proj [16384, 2560] FP8G (a, b in BF16 apart)", ld.format(0), 256, 16384 * H * G8),
        ("mixer", "out_proj, o_proj [2560, 6144] + shared gate-up [2560, 2560] FP8G, fused form", fq.format(0, 0, 1), 40,
         "fused40"),
        ("mixer", "q, k, v [13312, 2560] FP8G, verify and the FP8 drafter", ld.format(0), 208, 13312 * H * G8),
        ("shared expert", "down [2560, 1280] FP8G, fused form", ld.format(1), 40, H * 1280 * G8),
        ("read-outs", "down [324, 10240] 12-bit copy (hc_down_q12)", "tf_fn_hc_down_q12_kernel", 11, 324 * 10240 * Q12),
        ("read-outs", "up [10240, 320] 12-bit copy + mix (hc_upmix_q12)", "tf_fn_hc_upmix_q12_kernel", 320,
         10240 * 320 * Q12),
        ("drafter", "read-out down [320, 10240] FP8G (FP8 drafter)", fq.format(1, 1, 0), 5, 320 * 10240 * G8),
        ("drafter", "read-out up [10240, 320] FP8G (FP8 drafter)", fq.format(0, 0, 0), 160, 10240 * 320 * G8),
        ("router", "router [512, 2560] BF16", "_router", None, 512 * H * B16),
    ]

def main():
    stack, path = sys.argv[1], sys.argv[2]
    tables, gap, rounds, rows = 0, 0, 0, []
    for line in open(path, errors="replace"):
        if HEAD.match(line):
            tables += 1
            rounds, gap, rows = gap, 0, []
            continue
        m = ROW.match(line)
        if m:
            rows.append((float(m.group(1)), int(m.group(2)), int(m.group(4)), m.group(5).strip()))
            continue
        m = DONE.search(line)
        if m:
            gap += int(m.group(1))
    R = rounds
    rules = ours_rules() if stack == "ours" else prod_rules()
    agg = {}
    for ms, n, grid, sym in rows:
        for fam, label, key, g, b in rules:
            if key in sym and (g is None or g == grid):
                a = agg.setdefault(label, [fam, 0.0, 0, b])
                a[1] += ms
                a[2] += n
                break
    print(f"== {stack} {path}: {R} rounds")
    print("| family | weight and kernel | launches a round | ms a round | us a launch | MB a round | GB/s |")
    print("|---|---|---|---|---|---|---|")
    tot = {}
    for fam, label, key, g, b in rules:
        if label not in agg:
            continue
        _, ms, n, b = agg[label]
        L, T = n / R, ms / R
        if b == "fused40":  # 48 out/o_proj + 48 shared gate-up, the drafter's o_proj in the rest
            mb = (48 * H * 6144 * G8 + 48 * H * 2560 * G8 + max(L - 96, 0) * H * 6144 * G8) / 1e6
        else:
            mb = None if b is None else L * b / 1e6
        t = tot.setdefault(fam, [0.0, 0.0, True])
        t[0] += T
        if mb is None:
            t[2] = False
        else:
            t[1] += mb
        rate = f"{mb / T:.0f}" if mb else "-"
        mbs = f"{mb:,.0f}" if mb else "mixed shapes"
        print(f"| {fam} | {label} | {L:.2f} | {T:.3f} | {1000 * T / L:.1f} | {mbs} | {rate} |")
    for fam, (T, mb, whole) in tot.items():
        print(f"| {fam} | total | | {T:.3f} | | {mb:,.0f}{'' if whole else ' (known rows)'} | {mb / T if whole else 0:.0f} |")


if __name__ == "__main__":
    main()
