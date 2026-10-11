// Flash Next (qwen4_exp) torch ops on the CUDA engine's hot path, with torch's rounding points kept one for one.
// TensorFold 0.6.5 sources: nvfp4_moe.MoE4.shared_act, decode.Engine.sample_draft and forward.candidates; the fills
// replace Tensor.fill_ on 64-bit device scalars (gdn_io's conv pointer). Compile with -O3 --fmad=false --ftz=false
// (torch_ops/README.md); tools/zig/check_flashnext_ops.py compares raw bytes with torch.

#include <cuda_runtime.h>
#include <cuda_bf16.h>
#include <stdint.h>
#include "launch_shape.h"

// MoE4.shared_act, then `buf.act[:rows, top_k] = ...`: g [rows, 2 ni] bf16 (gate columns, then up) ->
// bf16(f32(bf16(gate / (1 + exp(-gate)))) * up), row r at out + r * out_stride. torch runs neg (exact), exp, add,
// div, the bf16 round trip and mul as separate fp32 kernels; each is one IEEE operation here.
extern "C" __global__ void tf_fn_shared_swiglu_kernel(const __nv_bfloat16* g, __nv_bfloat16* out, uint64_t rows,
                                                      uint64_t ni, uint64_t out_stride) {
    const uint64_t count = rows * ni;
    for (uint64_t i = uint64_t(blockIdx.x) * blockDim.x + threadIdx.x; i < count;
         i += uint64_t(gridDim.x) * blockDim.x) {
        const uint64_t r = i / ni;
        const uint64_t c = i - r * ni;
        const float gate = __bfloat162float(g[r * 2 * ni + c]);
        const float up = __bfloat162float(g[r * 2 * ni + ni + c]);
        const float e = expf(-gate);
        const float act = __fdiv_rn(gate, __fadd_rn(e, 1.0f));
        const float rounded = __bfloat162float(__float2bfloat16_rn(act));
        out[r * out_stride + c] = __float2bfloat16_rn(__fmul_rn(rounded, up));
    }
}

// bf16._reduce (F32: the K slices' fp32 partials summed in slice order) fused with glue._hc_act, the
// hyper-connection read-out's down projection [rows, ndn] -> act [rows, low] bf16 and, with ndn = low + streams,
// the inject gates [rows, streams] bf16. The operations are the Triton kernels' own (their SASS: v * 0.25 for v / S,
// cvt.rn.bf16, 0 - v, * log2(e) as 1.4426950216293334961f, ex2.approx.f32 without ftz, + 1, div.full.f32), so act and
// the gates have their bits; the 32-group sums of act (XS) are not written (only the 4-bit MTP matrices read them).
// Part slice s of row r at part + (s * rows + r) * ndn (the split _b16mm's layout). Grid (ceil(ndn / 128), rows).
__device__ __forceinline__ float tf_ex2_approx(float x) {
    float y;
    asm("ex2.approx.f32 %0, %1;" : "=f"(y) : "f"(x));
    return y;
}

__device__ __forceinline__ float tf_div_full(float a, float b) {
    float y;
    asm("div.full.f32 %0, %1, %2;" : "=f"(y) : "f"(a), "f"(b));
    return y;
}

__device__ __forceinline__ float tf_bf16_round(float x) {
    return __bfloat162float(__float2bfloat16_rn(x));
}

// glue._bsilu / _bsig's exp(-x): Triton's 0 - x, then exp as ex2.approx(x * log2(e))
__device__ __forceinline__ float tf_exp_neg(float x) {
    return tf_ex2_approx(__fmul_rn(__fsub_rn(0.0f, x), 1.4426950216293334961f));
}

extern "C" __global__ void tf_fn_hc_reduce_act_kernel(const float* part, __nv_bfloat16* act, __nv_bfloat16* inj,
                                                      uint32_t rows, uint32_t sk, uint32_t ndn, uint32_t low,
                                                      float inv_s) {
    const uint32_t r = blockIdx.y;
    const uint32_t i = blockIdx.x * blockDim.x + threadIdx.x;
    if (i >= ndn) return;
    const uint64_t total = uint64_t(rows) * ndn;
    const float* p = part + uint64_t(r) * ndn + i;
    float acc = p[0];
    for (uint32_t s = 1; s < sk; ++s) acc = __fadd_rn(acc, p[s * total]);
    const float v = tf_bf16_round(__fmul_rn(acc, inv_s));
    if (i < low) {
        // _bsilu: bf16(v / (1 + exp(-v)))
        const float a = tf_div_full(v, __fadd_rn(tf_exp_neg(v), 1.0f));
        act[uint64_t(r) * low + i] = __float2bfloat16_rn(a);
    } else {
        // 2 * _bsig: bf16(2 * bf16(1 / (1 + exp(-v))))
        const float g = tf_bf16_round(tf_div_full(1.0f, __fadd_rn(tf_exp_neg(v), 1.0f)));
        inj[uint64_t(r) * (ndn - low) + (i - low)] = __float2bfloat16_rn(__fmul_rn(2.0f, g));
    }
}

// Tensor.fill_ of `count` 64-bit words.
extern "C" __global__ void tf_fn_fill_u64_kernel(uint64_t* out, uint64_t value, uint64_t count) {
    for (uint64_t i = uint64_t(blockIdx.x) * blockDim.x + threadIdx.x; i < count;
         i += uint64_t(gridDim.x) * blockDim.x) out[i] = value;
}

// Engine.sample_draft, greedy: torch.cat([top, lse, col.float()]) of row = logits[:1].float(), where top, col =
// row.max(dim=-1) (the first maximum: `col` from the argmax of the same bf16 row, whose fp32 widening is exact).
extern "C" __global__ void tf_fn_draft_pick_kernel(const __nv_bfloat16* logits, const int32_t* col, const float* lse,
                                                   float* out) {
    if (blockIdx.x != 0 || threadIdx.x != 0) return;
    const int32_t c = *col;
    out[0] = __bfloat162float(logits[c]);
    out[1] = *lse;
    out[2] = __ll2float_rn((long long)c);
}

// Engine.sample_draft, sampled: torch.cat([vals, lse, idx.float()], dim=1) of one row's top-k (k values, int64
// columns) and its fp32 log-sum-exp -> out [2k + 1].
extern "C" __global__ void tf_fn_draft_pack_kernel(const float* vals, const int64_t* idx, const float* lse, float* out,
                                                   uint64_t k) {
    for (uint64_t i = uint64_t(blockIdx.x) * blockDim.x + threadIdx.x; i <= k;
         i += uint64_t(gridDim.x) * blockDim.x) {
        if (i == k) {
            out[k] = *lse;
            continue;
        }
        out[i] = vals[i];
        out[k + 1 + i] = __ll2float_rn((long long)idx[i]);
    }
}

// forward.candidates (two ranks): row r of c [rows, 2 cand + 1] = [vals | ids as int32 bits | lse], ids =
// (id_map[idx] if id_map else idx + offset).to(int32) (the low word, as torch narrows int64).
extern "C" __global__ void tf_fn_candidates_kernel(const float* vals, const int64_t* idx, const int64_t* id_map,
                                                   int64_t offset, const float* lse, float* out, uint64_t rows,
                                                   uint64_t cand) {
    const uint64_t r = blockIdx.x;
    if (r >= rows) return;
    float* row = out + r * (2 * cand + 1);
    for (uint64_t j = threadIdx.x; j <= cand; j += blockDim.x) {
        if (j == cand) {
            row[2 * cand] = lse[r];
            continue;
        }
        const int64_t i = idx[r * cand + j];
        const int64_t id = id_map ? id_map[i] : i + offset;
        row[j] = vals[r * cand + j];
        row[cand + j] = __int_as_float((int32_t)(uint32_t)(uint64_t)id);
    }
}

// sampling.nucleus_rows' fixed-point mass (top_k off): scaled = f64(f32(logit)) / t (torch: logits.float().double() /
// max(temperature, 1e-6)), mass = int64(floor(exp(scaled - top[r]) * 2^40)) (MASS), and each row's sum (an exact
// int64 sum in any order). torch runs the division, the subtraction, exp, the multiply and floor as separate fp64
// kernels: each is one IEEE operation here (exp is CUDA's fp64 exp, which torch's elementwise exp calls).
extern "C" __global__ void tf_fn_nucleus_mass_kernel(const __nv_bfloat16* logits, uint64_t ld, uint64_t cols, double t,
                                                     const double* top, int64_t* mass, unsigned long long* sums) {
    const uint64_t r = blockIdx.y;
    const uint64_t c = uint64_t(blockIdx.x) * blockDim.x + threadIdx.x;
    if (c >= cols) return;
    const double scaled = __ddiv_rn((double)__bfloat162float(logits[r * ld + c]), t);
    const double e = exp(__dsub_rn(scaled, top[r]));
    const int64_t m = (int64_t)floor(__dmul_rn(e, 1099511627776.0));
    mass[r * cols + c] = m;
    atomicAdd(&sums[r], (unsigned long long)m);
}

// nvfp4.matmul with one K slice (SK 1: the shared expert's gate/up, K 2560) and bf16-pattern tables (PACKED 0), the
// same bits as Triton's `_fp4mm` there: for each 16-input block b in order, p = HMMA.16816.F32.BF16(x rows, the
// block's 16 x 8 weights, C = 0) and acc = fma(p, S[b, n], acc) (the cubins' HMMA with RZ, then FFMA), the bf16 store
// rounding to nearest. `_fp4mm` runs a 64-column tile a program walking all of K, so 10 programs cover N 640 and the
// chain waits on each block's loads; here a warp owns 16 rows x 8 columns, a CTA 16 x 32, and the blocks stream
// through a STAGES-deep cp.async ring. X [M, K] bf16 rows x_stride apart; W the 64-column tiles of 16 x 64 blocks
// (tile t at t * (K / 64) * 64 * 64 elements, block b at b * 16 * 64, row k, column n % 64); S [K / 16, N] fp32.
#define TF_FP4S_STAGES 16
__device__ __forceinline__ void tf_cp16(void* smem, const void* g, bool ok) {
    const unsigned s = (unsigned)__cvta_generic_to_shared(smem);
    const int n = ok ? 16 : 0;
    asm volatile("cp.async.cg.shared.global [%0], [%1], 16, %2;\n" ::"r"(s), "l"(g), "r"(n) : "memory");
}
extern "C" __global__ void __launch_bounds__(128) tf_fn_fp4_serial_kernel(
        const __nv_bfloat16* __restrict__ X, const uint16_t* __restrict__ W, const float* __restrict__ S, void* OUT,
        uint32_t M, uint32_t N, uint32_t K, uint32_t x_stride, uint32_t f32_out) {
    __shared__ __align__(16) uint16_t xs[TF_FP4S_STAGES][16][16];
    __shared__ __align__(16) uint16_t ws[TF_FP4S_STAGES][16][32];
    __shared__ __align__(16) float ss[TF_FP4S_STAGES][32];
    const int tid = threadIdx.x, lane = tid & 31, warp = tid >> 5, g = lane >> 2, t = lane & 3;
    const uint32_t m0 = blockIdx.x * 16, n0 = blockIdx.y * 32;
    const uint32_t blocks = K / 16;
    const uint16_t* tile = W + (size_t)(n0 / 64) * ((K / 64) * 64 * 64) + (n0 % 64);
    // one stage: x 16 rows x 32 bytes (threads 0-31), w 16 rows x 64 bytes (32-95), s 128 bytes (96-103)
    auto load = [&](uint32_t b, int st) {
        if (tid < 32) {
            const uint32_t r = tid >> 1, h = tid & 1;
            const bool ok = m0 + r < M;
            const __nv_bfloat16* src = X + (size_t)(ok ? m0 + r : 0) * x_stride + b * 16 + h * 8;
            tf_cp16(&xs[st][r][h * 8], src, ok);
        } else if (tid < 96) {
            const uint32_t i = tid - 32, r = i >> 2, q = i & 3;
            tf_cp16(&ws[st][r][q * 8], tile + (size_t)b * 16 * 64 + r * 64 + q * 8, true);
        } else if (tid < 104) {
            const uint32_t q = tid - 96;
            tf_cp16(&ss[st][q * 4], S + (size_t)b * N + n0 + q * 4, true);
        }
        asm volatile("cp.async.commit_group;\n" ::: "memory");
    };
    for (int st = 0; st < TF_FP4S_STAGES - 1; ++st) {
        if ((uint32_t)st < blocks) load(st, st);
        else asm volatile("cp.async.commit_group;\n" ::: "memory");
    }
    float acc[4] = {0.f, 0.f, 0.f, 0.f};
    const int c = warp * 8 + g;  // this lane's B column within the CTA's 32
    for (uint32_t b = 0; b < blocks; ++b) {
        const int st = b % TF_FP4S_STAGES;
        asm volatile("cp.async.wait_group %0;\n" ::"n"(TF_FP4S_STAGES - 2) : "memory");
        __syncthreads();
        // the next block into the stage the previous step finished with
        const uint32_t nb = b + TF_FP4S_STAGES - 1;
        if (nb < blocks) load(nb, nb % TF_FP4S_STAGES);
        else asm volatile("cp.async.commit_group;\n" ::: "memory");
        // two bf16 a register, the lower k in the low half (no type punning of the uint16_t stage)
        const auto pair = [&](int r, int k) { return (uint32_t)xs[st][r][k] | ((uint32_t)xs[st][r][k + 1] << 16); };
        const uint32_t a0 = pair(g, 2 * t), a1 = pair(g + 8, 2 * t), a2 = pair(g, 2 * t + 8), a3 = pair(g + 8, 2 * t + 8);
        const uint32_t b0 = (uint32_t)ws[st][2 * t][c] | ((uint32_t)ws[st][2 * t + 1][c] << 16);
        const uint32_t b1 = (uint32_t)ws[st][2 * t + 8][c] | ((uint32_t)ws[st][2 * t + 9][c] << 16);
        float p0, p1, p2, p3;
        asm volatile("mma.sync.aligned.m16n8k16.row.col.f32.bf16.bf16.f32 {%0, %1, %2, %3}, {%4, %5, %6, %7}, "
                     "{%8, %9}, {%10, %10, %10, %10};\n"
                     : "=f"(p0), "=f"(p1), "=f"(p2), "=f"(p3)
                     : "r"(a0), "r"(a1), "r"(a2), "r"(a3), "r"(b0), "r"(b1), "f"(0.0f));
        const float s0 = ss[st][warp * 8 + 2 * t], s1 = ss[st][warp * 8 + 2 * t + 1];
        acc[0] = __fmaf_rn(p0, s0, acc[0]);
        acc[1] = __fmaf_rn(p1, s1, acc[1]);
        acc[2] = __fmaf_rn(p2, s0, acc[2]);
        acc[3] = __fmaf_rn(p3, s1, acc[3]);
    }
    asm volatile("cp.async.wait_group 0;\n" ::: "memory");
    const uint32_t col = n0 + warp * 8 + 2 * t;
#pragma unroll
    for (int h = 0; h < 2; ++h) {
        const uint32_t row = m0 + g + 8 * h;
        if (row >= M) continue;
        if (f32_out) {
            float* o = static_cast<float*>(OUT) + (size_t)row * N + col;
            o[0] = acc[2 * h];
            o[1] = acc[2 * h + 1];
        } else {
            __nv_bfloat16* o = static_cast<__nv_bfloat16*>(OUT) + (size_t)row * N + col;
            o[0] = __float2bfloat16_rn(acc[2 * h]);
            o[1] = __float2bfloat16_rn(acc[2 * h + 1]);
        }
    }
}

// C launchers for the development parity checks (tools/zig/check_flashnext_ops.py); Zig loads the fatbin.
extern "C" cudaError_t tf_fn_shared_swiglu(const void* g, void* out, uint64_t rows, uint64_t ni, uint64_t out_stride,
                                           cudaStream_t stream) {
    const uint64_t count = rows * ni;
    if (count == 0) return cudaSuccess;
    if (!g || !out || out_stride < ni) return cudaErrorInvalidValue;
    tf_fn_shared_swiglu_kernel<<<tf_launch_blocks(count, 256), 256, 0, stream>>>(
        static_cast<const __nv_bfloat16*>(g), static_cast<__nv_bfloat16*>(out), rows, ni, out_stride);
    return cudaGetLastError();
}

extern "C" cudaError_t tf_fn_fill_u64(void* out, uint64_t value, uint64_t count, cudaStream_t stream) {
    if (count == 0) return cudaSuccess;
    if (!out) return cudaErrorInvalidValue;
    tf_fn_fill_u64_kernel<<<tf_launch_blocks(count, 256), 256, 0, stream>>>(static_cast<uint64_t*>(out), value, count);
    return cudaGetLastError();
}

extern "C" cudaError_t tf_fn_draft_pick(const void* logits, const void* col, const void* lse, void* out,
                                        cudaStream_t stream) {
    if (!logits || !col || !lse || !out) return cudaErrorInvalidValue;
    tf_fn_draft_pick_kernel<<<1, 32, 0, stream>>>(static_cast<const __nv_bfloat16*>(logits),
        static_cast<const int32_t*>(col), static_cast<const float*>(lse), static_cast<float*>(out));
    return cudaGetLastError();
}

extern "C" cudaError_t tf_fn_draft_pack(const void* vals, const void* idx, const void* lse, void* out, uint64_t k,
                                        cudaStream_t stream) {
    if (!vals || !idx || !lse || !out) return cudaErrorInvalidValue;
    tf_fn_draft_pack_kernel<<<tf_launch_blocks(k + 1, 256), 256, 0, stream>>>(static_cast<const float*>(vals),
        static_cast<const int64_t*>(idx), static_cast<const float*>(lse), static_cast<float*>(out), k);
    return cudaGetLastError();
}

extern "C" cudaError_t tf_fn_candidates(const void* vals, const void* idx, const void* id_map, int64_t offset,
                                        const void* lse, void* out, uint64_t rows, uint64_t cand,
                                        cudaStream_t stream) {
    if (rows == 0) return cudaSuccess;
    if (!vals || !idx || !lse || !out || rows > 65535) return cudaErrorInvalidValue;
    tf_fn_candidates_kernel<<<uint32_t(rows), 64, 0, stream>>>(static_cast<const float*>(vals),
        static_cast<const int64_t*>(idx), static_cast<const int64_t*>(id_map), offset, static_cast<const float*>(lse),
        static_cast<float*>(out), rows, cand);
    return cudaGetLastError();
}

extern "C" cudaError_t tf_fn_nucleus_mass(const void* logits, uint64_t ld, uint64_t rows, uint64_t cols, double t,
                                          const void* top, void* mass, void* sums, cudaStream_t stream) {
    if (rows == 0 || cols == 0) return cudaSuccess;
    if (!logits || !top || !mass || !sums || rows > 65535) return cudaErrorInvalidValue;
    cudaError_t e = cudaMemsetAsync(sums, 0, rows * sizeof(unsigned long long), stream);
    if (e != cudaSuccess) return e;
    tf_fn_nucleus_mass_kernel<<<dim3(uint32_t((cols + 255) / 256), uint32_t(rows)), 256, 0, stream>>>(
        static_cast<const __nv_bfloat16*>(logits), ld, cols, t, static_cast<const double*>(top),
        static_cast<int64_t*>(mass), static_cast<unsigned long long*>(sums));
    return cudaGetLastError();
}

// The hyper-connection read-outs' bf16 matrices at decode widths from a lossless 12-bit copy (q12), with
// the Triton kernels' bits (tf_fn_hc_down_q12_kernel = bf16._b16mm's split-K partials then
// tf_fn_hc_reduce_act_kernel; tf_fn_hc_upmix_q12_kernel = prompt_mm._hc_up_mix = _b16mm (SK 1) + glue._hc_mix).
// An output's partial is the same mma.m16n8k16 chain Triton issues (the slice's k16 chunks ascending from a zero
// accumulator), so tiles and warps are free; the slice sums and the epilogues are tf_fn_hc_reduce_act_kernel's.
// q12 block = one n8 tile x 64 k (512 weights, 32 lanes x 16): lane l = 4 g + q holds row 8 t + g and, for chunk c,
// k = 16 c + {2q, 2q+1, 2q+8, 2q+9} (weight j = 4 c + i). sm: the 16 sign|mantissa bytes; ex: 4-bit codes, weight
// j = 2 p + h at word h, byte p & 3, nibble p >> 2, the exponent = base - code; code 15 = escape (exact bits in the
// block's list esc[escoff[blk] ..], entries pos << 16 | bits with pos = 16 lane + j, sorted); base: the (row, 64 k)
// maximum exponent. tf_fn_hc_q12_pack_kernel writes it (hc-check: an exact round trip).
namespace tf_hcq {

__device__ __forceinline__ uint32_t smem_u32(const void* p) {
    return static_cast<uint32_t>(__cvta_generic_to_shared(p));
}

struct Q12 {
    const uint4* sm;
    const uint2* ex;
    const uint8_t* base;
    const uint32_t* escoff;
    const uint32_t* esc;
};

struct Raw {
    uint4 sm;
    uint2 ex;
    uint32_t base;
};

__device__ __forceinline__ void load_block(Raw& r, const Q12& w, uint32_t blk, int lane) {
    const size_t i = size_t(blk) * 32 + lane;
    r.sm = __ldg(w.sm + i);
    r.ex = __ldg(w.ex + i);
    r.base = __ldg(w.base + size_t(blk) * 8 + (lane >> 2));
}

__device__ __noinline__ uint32_t escape_bits(const uint32_t* esc, uint32_t e0, uint32_t e1, uint32_t pos) {
    for (uint32_t e = e0; e < e1; ++e) {
        const uint32_t v = __ldg(esc + e);
        if ((v >> 16) == pos) return v & 0xFFFFu;
    }
    return 0;
}

// The lane's 16 weights as 8 bf16 pairs (b0, b1 of chunk c = o[2c], o[2c + 1]).
__device__ __forceinline__ void decode(uint32_t (&o)[8], const Raw& r, const Q12& w, uint32_t blk, int lane) {
    const uint32_t sw[4] = {r.sm.x, r.sm.y, r.sm.z, r.sm.w};
    // base << 7 in both halves, a guard bit above each so a borrow never crosses halves
    const uint32_t bwd = (r.base * 0x00800080u) | 0x80008000u;
#pragma unroll
    for (int p = 0; p < 8; ++p) {
        const uint32_t sa = 2u * (p & 1), sb = sa + 1u;
        // the stored s|m7 bytes into bytes 0 and 2, their signs replicated into bytes 1 and 3
        const uint32_t x = __byte_perm(sw[p >> 1], 0u, sa | ((sa | 8u) << 4) | (sb << 8) | ((sb | 8u) << 12));
        const uint32_t z = __byte_perm(r.ex.x, r.ex.y, uint32_t(p & 3) | (uint32_t(4 + (p & 3)) << 8));
        const uint32_t off = p < 4 ? (z & 0x000F000Fu) * 128u : (z & 0x00F000F0u) * 8u;
        o[p] = (x & 0x807F807Fu) | ((bwd - off) & 0x7F807F80u);
    }
    const uint32_t mx = r.ex.x & (r.ex.x >> 1) & (r.ex.x >> 2) & (r.ex.x >> 3) & 0x11111111u;
    const uint32_t my = r.ex.y & (r.ex.y >> 1) & (r.ex.y >> 2) & (r.ex.y >> 3) & 0x11111111u;
    if (mx | my) {
        const uint32_t e0 = __ldg(w.escoff + blk), e1 = __ldg(w.escoff + blk + 1);
#pragma unroll 1
        for (int k = 0; k < 16; ++k) {
            const uint32_t h = k >> 3, nib = k & 7;
            if (!(((h ? my : mx) >> (4 * nib)) & 1)) continue;
            const int p = (nib >> 1) + 4 * (nib & 1), j = 2 * p + h;
            const uint32_t bits = escape_bits(w.esc, e0, e1, uint32_t(16 * lane + j));
            const uint32_t sh = 16u * h, keep = ~(0xFFFFu << sh);
#pragma unroll
            for (int pp = 0; pp < 8; ++pp) o[pp] = pp == p ? ((o[pp] & keep) | (bits << sh)) : o[pp];
        }
    }
}

__device__ __forceinline__ void mma(float (&d)[4], const uint32_t (&a)[4], uint32_t b0, uint32_t b1) {
    asm volatile(
        "mma.sync.aligned.m16n8k16.row.col.f32.bf16.bf16.f32 {%0, %1, %2, %3}, {%4, %5, %6, %7}, {%8, %9}, "
        "{%0, %1, %2, %3};\n"
        : "+f"(d[0]), "+f"(d[1]), "+f"(d[2]), "+f"(d[3])
        : "r"(a[0]), "r"(a[1]), "r"(a[2]), "r"(a[3]), "r"(b0), "r"(b1));
}

// A fragment of chunk kc (ldmatrix x4: lane l addresses row l & 15 at k 16 kc + 8 (l >> 4)).
__device__ __forceinline__ void a_frag(uint32_t (&a)[4], const uint8_t* xs, int pitch, int kc, int lane) {
    const uint8_t* p = xs + (lane & 15) * pitch + (16 * kc + 8 * (lane >> 4)) * 2;
    asm volatile("ldmatrix.sync.aligned.m8n8.x4.shared.b16 {%0, %1, %2, %3}, [%4];\n"
                 : "=r"(a[0]), "=r"(a[1]), "=r"(a[2]), "=r"(a[3])
                 : "r"(smem_u32(p)));
}

// Rows [r0, r0 + 16 RT) x k [k0, k0 + KW) of x (rows `stride` elements apart) into xs, rows >= M zero (Triton's
// other=0.0).
template <int KW, int RT>
__device__ __forceinline__ void stage(uint8_t* xs, const __nv_bfloat16* x, size_t stride, int M, int r0, int k0) {
    constexpr int CH = KW * 2 / 16, PITCH = KW * 2 + 16;
    for (int i = threadIdx.x; i < 16 * RT * CH; i += blockDim.x) {
        const int r = i / CH, c = i - r * CH;
        const bool ok = r0 + r < M;
        const __nv_bfloat16* src = x + (ok ? size_t(r0 + r) * stride + k0 + c * 8 : 0);
        asm volatile("cp.async.cg.shared.global [%0], [%1], 16, %2;\n" ::"r"(smem_u32(xs + r * PITCH + c * 16)),
                     "l"(src), "r"(ok ? 16 : 0));
    }
    asm volatile("cp.async.commit_group;\ncp.async.wait_group 0;\n" ::);
    __syncthreads();
}

// NB blocks of tile t from block blk0 for RT row tiles (xs + 16 rows a tile), chunks in order (MUT: reversed inside
// each block, hc-check's mutant); each output's chain is its own accumulator, so the row tiles only interleave.
template <int NB, int RT, bool MUT>
__device__ __forceinline__ void chain_t(float (&d)[RT][4], const Raw (&raw)[NB], const Q12& w, uint32_t blk0,
                                        const uint8_t* xs, int pitch, int lane) {
#pragma unroll
    for (int i = 0; i < NB; ++i) {
        uint32_t bw[8];
        decode(bw, raw[i], w, blk0 + i, lane);
#pragma unroll
        for (int c0 = 0; c0 < 4; ++c0) {
            const int c = MUT ? 3 - c0 : c0;
#pragma unroll
            for (int rt = 0; rt < RT; ++rt) {
                uint32_t a[4];
                a_frag(a, xs + rt * 16 * pitch, pitch, 4 * i + c, lane);
                mma(d[rt], a, bw[2 * c], bw[2 * c + 1]);
            }
        }
    }
}

template <int NB, int RT>
__device__ __forceinline__ void chain(float (&d)[RT][4], const Raw (&raw)[NB], const Q12& w, uint32_t blk0,
                                      const uint8_t* xs, int pitch, int lane, int mut) {
    if (mut == 1)
        chain_t<NB, RT, true>(d, raw, w, blk0, xs, pitch, lane);
    else
        chain_t<NB, RT, false>(d, raw, w, blk0, xs, pitch, lane);
}

}  // namespace tf_hcq

// Down + reduce + act: x [M, K] (rows x_stride apart) @ W [N, K].T from q12, K slices of 320 (SK = K / 320 =
// gridDim.y), the slices' fp32 partials to part [SK, M, N] (the split _b16mm's layout). With counters (else partials
// only, for tf_fn_hc_reduce_act_kernel) the CTA arriving last at its column group (counters[blockIdx.x], reset by it)
// sums them in slice order into act [M, low] / inj [M, N - low] as tf_fn_hc_reduce_act_kernel does. Grid
// (ceil(ceil(N / 8) / 4), SK, ceil(M / (16 RT))), 128 threads; warp w: tile 4 blockIdx.x + w, rows 16 RT blockIdx.z ...
// (RT 1 to 16 rows, else 2: the weights decoded once for 32 rows).
template <int RT>
__device__ __forceinline__ void hc_down_q12(const __nv_bfloat16* __restrict__ x, uint32_t x_stride, uint32_t M,
                                            const tf_hcq::Q12& w, float* __restrict__ part, uint32_t N, uint32_t K,
                                            __nv_bfloat16* act, __nv_bfloat16* inj, uint32_t low, float inv_s,
                                            uint32_t* counters, int mut) {
    using namespace tf_hcq;
    constexpr int KS = 320, NB = KS / 64, PITCH = KS * 2 + 16;
    __shared__ __align__(16) uint8_t xs[16 * RT * PITCH];
    __shared__ int last;
    const int lane = threadIdx.x & 31, warp = threadIdx.x >> 5, g = lane >> 2, q = lane & 3;
    const uint32_t tiles = (N + 7) / 8, NBK = K / 64, SK = gridDim.y, s = blockIdx.y, r0 = 16 * RT * blockIdx.z;
    const uint32_t t = blockIdx.x * 4 + warp;
    const bool live = t < tiles;
    const uint32_t blk0 = t * NBK + s * NB;
    Raw raw[NB];
    if (live) {
#pragma unroll
        for (int i = 0; i < NB; ++i) load_block(raw[i], w, blk0 + i, lane);
    }
    stage<KS, RT>(xs, x, x_stride, int(M), int(r0), int(s * KS));
    if (live) {
        float d[RT][4] = {};
        chain<NB, RT>(d, raw, w, blk0, xs, PITCH, lane, mut);
        const uint32_t n = 8 * t + 2 * q;
        float* p = part + size_t(s) * M * N;
#pragma unroll
        for (int rt = 0; rt < RT; ++rt) {
            const uint32_t ra = r0 + 16 * rt + g, rb = ra + 8;
            if (ra < M) {
                if (n < N) p[size_t(ra) * N + n] = d[rt][0];
                if (n + 1 < N) p[size_t(ra) * N + n + 1] = d[rt][1];
            }
            if (rb < M) {
                if (n < N) p[size_t(rb) * N + n] = d[rt][2];
                if (n + 1 < N) p[size_t(rb) * N + n + 1] = d[rt][3];
            }
        }
    }
    if (counters == nullptr) return;
    __threadfence();
    __syncthreads();
    if (threadIdx.x == 0) last = atomicAdd(counters + blockIdx.x, 1u) == SK * gridDim.z - 1;
    __syncthreads();
    if (!last) return;
    __threadfence();
    const uint32_t c0 = 32 * blockIdx.x, cols = min(N, c0 + 32) - c0;
    const size_t total = size_t(M) * N;
    for (uint32_t e = threadIdx.x; e < M * cols; e += blockDim.x) {
        const uint32_t r = e / cols, i = c0 + e - r * cols;
        const float* pp = part + size_t(r) * N + i;
        // all slices' partials in flight at once, then added in slice order (SK <= 32, the launcher's bound)
        float pv[32];
#pragma unroll
        for (uint32_t ss = 0; ss < 32; ++ss) pv[ss] = ss < SK ? __ldcg(pp + ss * total) : 0.0f;
        float acc = pv[0];
#pragma unroll
        for (uint32_t ss = 1; ss < 32; ++ss)
            if (ss < SK) acc = __fadd_rn(acc, pv[ss]);
        const float v = tf_bf16_round(__fmul_rn(acc, inv_s));
        if (i < low) {
            act[size_t(r) * low + i] = __float2bfloat16_rn(tf_div_full(v, __fadd_rn(tf_exp_neg(v), 1.0f)));
        } else {
            const float gt = tf_bf16_round(tf_div_full(1.0f, __fadd_rn(tf_exp_neg(v), 1.0f)));
            inj[size_t(r) * (N - low) + (i - low)] = __float2bfloat16_rn(__fmul_rn(2.0f, gt));
        }
    }
    if (threadIdx.x == 0) counters[blockIdx.x] = 0;
}

extern "C" __global__ void __launch_bounds__(128) tf_fn_hc_down_q12_kernel(
    const __nv_bfloat16* __restrict__ x, uint32_t x_stride, uint32_t M, const uint4* sm, const uint2* ex,
    const uint8_t* base, const uint32_t* escoff, const uint32_t* esc, float* __restrict__ part, uint32_t N, uint32_t K,
    __nv_bfloat16* act, __nv_bfloat16* inj, uint32_t low, float inv_s, uint32_t* counters, int mut) {
    hc_down_q12<1>(x, x_stride, M, tf_hcq::Q12{sm, ex, base, escoff, esc}, part, N, K, act, inj, low, inv_s, counters, mut);
}

extern "C" __global__ void __launch_bounds__(128) tf_fn_hc_down_q12_r32_kernel(
    const __nv_bfloat16* __restrict__ x, uint32_t x_stride, uint32_t M, const uint4* sm, const uint2* ex,
    const uint8_t* base, const uint32_t* escoff, const uint32_t* esc, float* __restrict__ part, uint32_t N, uint32_t K,
    __nv_bfloat16* act, __nv_bfloat16* inj, uint32_t low, float inv_s, uint32_t* counters, int mut) {
    hc_down_q12<2>(x, x_stride, M, tf_hcq::Q12{sm, ex, base, escoff, esc}, part, N, K, act, inj, low, inv_s, counters, mut);
}

// Up + mix: act [M, 320] contiguous, W [S D, 320] from q12, normed [M, S D] -> mixed [M, D] =
// bf16((sum_s in order bf16(bsig(bf16(u_s)) * normed_s)) * (1 / S)), S = 4. Grid (D / 8, ceil(M / (16 RT))), 128
// threads (warp = stream), rows 16 RT blockIdx.y ...
template <int RT>
__device__ __forceinline__ void hc_upmix_q12(const __nv_bfloat16* __restrict__ actv, const tf_hcq::Q12& w,
                                             const __nv_bfloat16* __restrict__ normed,
                                             __nv_bfloat16* __restrict__ mixed, uint32_t M, uint32_t D, int mut) {
    using namespace tf_hcq;
    constexpr int KW = 320, S = 4, NB = KW / 64, PITCH = KW * 2 + 16;
    __shared__ __align__(16) uint8_t xs[16 * RT * PITCH];
    __shared__ float term[S][16 * RT][8];
    const int lane = threadIdx.x & 31, s = threadIdx.x >> 5, g = lane >> 2, q = lane & 3;
    const uint32_t d0 = blockIdx.x * 8, t = (s * D + d0) / 8, blk0 = t * NB, r0 = 16 * RT * blockIdx.y;
    Raw raw[NB];
#pragma unroll
    for (int i = 0; i < NB; ++i) load_block(raw[i], w, blk0 + i, lane);
    // this lane's normed values, loaded before the chain (they do not depend on it)
    float nv[RT][4];
#pragma unroll
    for (int rt = 0; rt < RT; ++rt)
#pragma unroll
        for (int h = 0; h < 4; ++h) {
            const uint32_t r = r0 + 16 * rt + g + 8 * (h >> 1), c = 2 * q + (h & 1);
            nv[rt][h] = r < M ? __bfloat162float(normed[size_t(r) * (S * D) + size_t(s) * D + d0 + c]) : 0.0f;
        }
    stage<KW, RT>(xs, actv, KW, int(M), int(r0), 0);
    float d[RT][4] = {};
    chain<NB, RT>(d, raw, w, blk0, xs, PITCH, lane, mut);
#pragma unroll
    for (int rt = 0; rt < RT; ++rt)
#pragma unroll
        for (int h = 0; h < 4; ++h) {
            const uint32_t r = 16 * rt + g + 8 * (h >> 1), c = 2 * q + (h & 1);
            float v = 0.f;
            if (r0 + r < M) {
                // glue._bsig(u) * n: bf16(1 / (1 + exp(-u))), the product rounded to bf16
                const float u = tf_bf16_round(d[rt][h]);
                const float sg = tf_bf16_round(tf_div_full(1.0f, __fadd_rn(1.0f, tf_exp_neg(u))));
                v = tf_bf16_round(__fmul_rn(sg, nv[rt][h]));
            }
            term[s][r][c] = v;
        }
    __syncthreads();
    for (uint32_t e = threadIdx.x; e < 16 * RT * 8; e += blockDim.x) {
        const uint32_t r = e >> 3, c = e & 7;
        if (r0 + r < M) {
            float total = 0.0f;
#pragma unroll
            for (int ss = 0; ss < S; ++ss) total = __fadd_rn(total, term[ss][r][c]);
            mixed[size_t(r0 + r) * D + d0 + c] = __float2bfloat16_rn(__fmul_rn(total, 1.0f / S));
        }
    }
}

extern "C" __global__ void __launch_bounds__(128) tf_fn_hc_upmix_q12_kernel(
    const __nv_bfloat16* __restrict__ actv, const uint4* sm, const uint2* ex, const uint8_t* base,
    const uint32_t* escoff, const uint32_t* esc, const __nv_bfloat16* __restrict__ normed,
    __nv_bfloat16* __restrict__ mixed, uint32_t M, uint32_t D, int mut) {
    hc_upmix_q12<1>(actv, tf_hcq::Q12{sm, ex, base, escoff, esc}, normed, mixed, M, D, mut);
}

extern "C" __global__ void __launch_bounds__(128) tf_fn_hc_upmix_q12_r32_kernel(
    const __nv_bfloat16* __restrict__ actv, const uint4* sm, const uint2* ex, const uint8_t* base,
    const uint32_t* escoff, const uint32_t* esc, const __nv_bfloat16* __restrict__ normed,
    __nv_bfloat16* __restrict__ mixed, uint32_t M, uint32_t D, int mut) {
    hc_upmix_q12<2>(actv, tf_hcq::Q12{sm, ex, base, escoff, esc}, normed, mixed, M, D, mut);
}

// The q12 packer: grid (tiles, K / 64), one warp a block. pack 0 writes each block's escape count to counts; pack 1
// the codes, bases and escapes (at escoff[blk], position order). Rows >= n (the last tile's padding) are zeros.
extern "C" __global__ void __launch_bounds__(32) tf_fn_hc_q12_pack_kernel(
    const uint16_t* __restrict__ w, uint32_t n, uint32_t k, uint32_t* counts, uint4* sm, uint2* ex, uint8_t* base,
    const uint32_t* escoff, uint32_t* esc, int pack) {
    const uint32_t t = blockIdx.x, b = blockIdx.y, nbk = k / 64, lane = threadIdx.x, g = lane >> 2, q = lane & 3;
    const uint32_t blk = t * nbk + b, row = 8 * t + g;
    uint32_t v[16];
#pragma unroll
    for (int c = 0; c < 4; ++c) {
        uint32_t lo = 0, hi = 0;
        if (row < n) {
            const uint32_t* p = reinterpret_cast<const uint32_t*>(w + size_t(row) * k + 64 * b + 16 * c + 2 * q);
            lo = p[0];
            hi = p[4];
        }
        v[4 * c] = lo & 0xFFFFu;
        v[4 * c + 1] = lo >> 16;
        v[4 * c + 2] = hi & 0xFFFFu;
        v[4 * c + 3] = hi >> 16;
    }
    uint32_t mx = 0;
#pragma unroll
    for (int j = 0; j < 16; ++j) mx = max(mx, (v[j] >> 7) & 0xFFu);
    mx = max(mx, __shfl_xor_sync(0xFFFFFFFFu, mx, 1));
    mx = max(mx, __shfl_xor_sync(0xFFFFFFFFu, mx, 2));
    uint32_t flags = 0, smw[4] = {0, 0, 0, 0}, exw[2] = {0, 0};
#pragma unroll
    for (int j = 0; j < 16; ++j) {
        const uint32_t off = mx - ((v[j] >> 7) & 0xFFu);
        const uint32_t code = off > 14 ? 15u : off;
        if (code == 15) flags |= 1u << j;
        smw[j >> 2] |= (((v[j] >> 8) & 0x80u) | (v[j] & 0x7Fu)) << (8 * (j & 3));
        const int h = j & 1, p = j >> 1;
        exw[h] |= code << (8 * (p & 3) + 4 * (p >> 2));
    }
    const uint32_t cnt = __popc(flags);
    if (!pack) {
        uint32_t s = cnt;
        for (int o = 16; o; o >>= 1) s += __shfl_xor_sync(0xFFFFFFFFu, s, o);
        if (lane == 0) counts[blk] = s;
        return;
    }
    const size_t i = size_t(blk) * 32 + lane;
    sm[i] = make_uint4(smw[0], smw[1], smw[2], smw[3]);
    ex[i] = make_uint2(exw[0], exw[1]);
    if (q == 0) base[size_t(blk) * 8 + g] = uint8_t(mx);
    uint32_t pre = cnt;
    for (int o = 1; o < 32; o <<= 1) {
        const uint32_t y = __shfl_up_sync(0xFFFFFFFFu, pre, o);
        if (lane >= uint32_t(o)) pre += y;
    }
    uint32_t at = escoff[blk] + pre - cnt;
#pragma unroll
    for (int j = 0; j < 16; ++j)
        if (flags >> j & 1) esc[at++] = ((16u * lane + j) << 16) | v[j];
}
