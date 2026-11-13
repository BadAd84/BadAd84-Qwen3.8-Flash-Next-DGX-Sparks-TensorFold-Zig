# fp8res.sh [TAG] - nvcc 13.3 resources of flashnext_attn.cu's fp8 and paged launches on the patched tree (rungs127/TAG.patch
# on v1.2.7), for sm_80, sm_86, sm_89, sm_120 and sm_121 in that order, with cuda_kernels.zig's glue flags and torch's.
set -euo pipefail
D=~/work/lanes/fp8pg
mkdir -p "$D"
[ -d "$D/tf/.git" ] || git clone -q git://192.168.99.16/up-pr/tf "$D/tf"
cd "$D/tf"
git checkout -q -f 93a2e93ecebff8aa52b88e58c5dd222516e69c5f
git clean -qfdx
git apply --whitespace=nowarn ~/work/target/rungs127/"${1:-fp8pg}".patch
docker run --rm --network none -v "$D/tf:/tf" -w /tf nvcr.io/nvidia/pytorch:26.07-py3 bash -c '
set -e
nvcc --version | grep -i release
nvcc -fatbin -D__CUDA_NO_HALF_OPERATORS__ -D__CUDA_NO_HALF_CONVERSIONS__ -D__CUDA_NO_BFLOAT16_CONVERSIONS__ \
  -D__CUDA_NO_HALF2_OPERATORS__ --expt-relaxed-constexpr -std=c++20 -O3 --fmad=false --ftz=false --prec-div=true \
  --prec-sqrt=true -I zig/kernels/cuda -gencode=arch=compute_80,code=sm_80 -gencode=arch=compute_86,code=sm_86 \
  -gencode=arch=compute_89,code=sm_89 -gencode=arch=compute_120,code=sm_120 -gencode=arch=compute_121,code=sm_121 \
  -o /tmp/a.fatbin zig/kernels/cuda/flashnext_attn.cu
cuobjdump --dump-resource-usage /tmp/a.fatbin > /tmp/u.txt
python3 - <<EOF
import re
t = open("/tmp/u.txt").read()
b = re.split(r"arch = (sm_\d+)", t)
for i in range(1, len(b), 2):
    for m in re.finditer(r"Function (fn_attn_\w*(?:kv8|paged)\w*):\s*\n\s*([^\n]*)", b[i + 1]):
        print(b[i], m.group(1), m.group(2))
EOF
'
