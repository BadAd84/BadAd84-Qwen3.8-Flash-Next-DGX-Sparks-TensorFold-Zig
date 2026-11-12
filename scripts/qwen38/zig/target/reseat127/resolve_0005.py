#!/usr/bin/env python3
"""resolve_0005.py TREE - patch 0005 (prompt chunk, the relaxed MX128 tile) on v1.2.7: qmmf.cu.

v1.2.7 only appended to the file (its native FP4 decode check, at file scope after the namespace's closing brace)
and our patch changes the file's last lines. Our side stays whole, with upstream's block after it.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from appended import keep_appended  # noqa: E402

n = keep_appended(sys.argv[1].rstrip("/\\"), "zig/kernels/cuda/qmmf.cu", b"tf_qmmf_native_fp4_check")
print(f"resolve_0005: qmmf.cu resolved (our kernels, then upstream's appended {n}-line native FP4 check)")
