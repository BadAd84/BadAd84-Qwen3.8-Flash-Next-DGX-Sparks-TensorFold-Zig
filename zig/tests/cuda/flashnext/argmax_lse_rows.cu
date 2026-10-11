// argmax_lse_rows.cu: the two row kernels patches/0010 launches with 1024 threads, checked on the GPU at every
// power-of-two block from 32 to 1024 threads: tf_fn_lse_max_kernel (fn_logsumexp.cu: the strided loop, its 4-wide
// unroll and remainder, then the shared-memory tree over the whole block) and tf_argmax_rows_i32_kernel (argmax.cu: the
// warp tree over up to 32 warps' partials). Every block size must give the same bits, and each row must match a host
// reference (the maximum with NaN winning and |max| == inf set to 0; the first NaN, else the first maximum).
//
// Rows: random values; ties at the first and last column; the maximum in the 4-wide loop's remainder; the maximum
// or the only NaN at column 1023 or 511 (the last thread of a 1024 or 512 block: the tree's last steps must carry it);
// -inf rows; +inf; NaN; -0/+0 only. Widths 248,320 (the vocabulary), 79,591 (the draft vocabulary, odd), 1, 7, 1,024,
// 4,097 (one past 4 x 1024). Build and run on the GPU from the TensorFold checkout (sm_121 shown):
//   nvcc -O2 -arch=sm_121 -rdc=true --fmad=false -I zig/kernels/cuda/torch_ops -o argmax_lse_rows \
//     zig/tests/cuda/flashnext/argmax_lse_rows.cu zig/kernels/cuda/torch_ops/argmax.cu \
//     zig/kernels/cuda/torch_ops/fn_logsumexp.cu && ./argmax_lse_rows
// Exit 0: every row equal at every block size and to the host reference.
#include <cuda_bf16.h>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

extern "C" __global__ void tf_argmax_rows_i32_kernel(const void*, int32_t*, int64_t, int64_t, int64_t, int32_t);
extern "C" __global__ void tf_fn_lse_max_kernel(const float*, float*, uint32_t, uint32_t);

static uint32_t rng = 12345u;
static uint32_t next() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static float frand() { return (int32_t(next()) >> 8) * (1.0f / 8388608.0f) * 30.0f; }
static uint16_t bf(float f) { uint32_t u; memcpy(&u, &f, 4); return uint16_t(u >> 16); }
static float unbf(uint16_t h) { uint32_t u = uint32_t(h) << 16; float f; memcpy(&f, &u, 4); return f; }

enum Kind { RANDOM, TIE_FIRST, TIE_LAST, TAIL_MAX, MAX_T1023, MAX_T511, NAN_T1023, NAN_T511, NEG_INF, POS_INF, NAN_MID, ZEROS, KINDS };

static void fill(std::vector<float>& r, int kind) {
  const size_t n = r.size();
  for (auto& v : r) v = frand();
  const float big = 1000.f;
  switch (kind) {
    case TIE_FIRST: r[0] = big; r[n / 2] = big; break;
    case TIE_LAST: r[n - 1] = big; if (n > 1) r[n - 2] = big; break;
    case TAIL_MAX: r[n - 1 - (n > 3 ? 2 : 0)] = big; break;
    case MAX_T1023: r[n > 1023 ? 1023 : n - 1] = big; break;
    case MAX_T511: r[n > 511 ? 511 : n - 1] = big; break;
    case NAN_T1023: r[n > 1023 ? 1023 : n - 1] = NAN; break;
    case NAN_T511: r[n > 511 ? 511 : n - 1] = NAN; break;
    case NEG_INF: for (auto& v : r) v = -INFINITY; break;
    case POS_INF: r[n / 3] = INFINITY; r[n - 1] = INFINITY; break;
    case NAN_MID: r[n / 2] = NAN; if (n > 2) r[n - 1] = NAN; break;
    case ZEROS: for (size_t i = 0; i < n; ++i) r[i] = (i & 1) ? -0.0f : 0.0f; break;
    default: break;
  }
}

// fn_logsumexp.cu's rule: NaN wins, then |max| == inf is 0
static float refMax(const float* r, size_t n) {
  float m = -INFINITY;
  for (size_t i = 0; i < n; ++i) {
    if (r[i] != r[i]) return NAN;
    if (r[i] > m) m = r[i];
  }
  return std::fabs(m) == INFINITY ? 0.0f : m;
}

// argmax.cu's rule on the bf16 row: the first NaN, else the first maximum (+0 and -0 equal)
static int32_t refArgmax(const uint16_t* r, size_t n) {
  int32_t best = 0;
  float bv = unbf(r[0]);
  if (bv != bv) return 0;
  for (size_t i = 1; i < n; ++i) {
    const float v = unbf(r[i]);
    if (v != v) return int32_t(i);
    if (v > bv) { bv = v; best = int32_t(i); }
  }
  return best;
}

int main() {
  const int64_t widths[] = {248320, 79591, 1, 7, 1024, 4097};
  const int blocks[] = {32, 64, 128, 256, 512, 1024};
  const int NB = sizeof(blocks) / sizeof(blocks[0]);
  int bad = 0, rows_checked = 0;
  for (int64_t n : widths) {
    const int R = KINDS * 2;
    std::vector<float> h(size_t(R) * n);
    std::vector<uint16_t> hb(h.size());
    for (int r = 0; r < R; ++r) {
      std::vector<float> row(n);
      fill(row, r % KINDS);
      memcpy(&h[size_t(r) * n], row.data(), n * 4);
    }
    for (size_t i = 0; i < h.size(); ++i) hb[i] = bf(h[i]);
    float* dx; uint16_t* db; float* dm; int32_t* da;
    cudaMalloc(&dx, h.size() * 4); cudaMalloc(&db, hb.size() * 2);
    cudaMalloc(&dm, size_t(NB) * R * 4); cudaMalloc(&da, size_t(NB) * R * 4);
    cudaMemcpy(dx, h.data(), h.size() * 4, cudaMemcpyHostToDevice);
    cudaMemcpy(db, hb.data(), hb.size() * 2, cudaMemcpyHostToDevice);
    cudaMemset(dm, 0xA5, size_t(NB) * R * 4); cudaMemset(da, 0xA5, size_t(NB) * R * 4);
    for (int b = 0; b < NB; ++b) {
      tf_fn_lse_max_kernel<<<R, blocks[b]>>>(dx, dm + b * R, R, uint32_t(n));
      tf_argmax_rows_i32_kernel<<<R, blocks[b]>>>(db, da + b * R, R, n, n, 0);
    }
    if (cudaDeviceSynchronize() != cudaSuccess) { printf("FAIL launch at width %lld\n", (long long)n); return 2; }
    std::vector<float> m(size_t(NB) * R); std::vector<int32_t> a(size_t(NB) * R);
    cudaMemcpy(m.data(), dm, m.size() * 4, cudaMemcpyDeviceToHost);
    cudaMemcpy(a.data(), da, a.size() * 4, cudaMemcpyDeviceToHost);
    for (int r = 0; r < R; ++r) {
      ++rows_checked;
      const float want = refMax(&h[size_t(r) * n], n);
      const int32_t want_a = refArgmax(&hb[size_t(r) * n], n);
      const float top = m[(NB - 1) * R + r];  // the engine's launch: 1024 threads
      if (want != want ? top == top : top != want) {
        ++bad; printf("lse max differs from the host: width %lld row %d kind %d: %g vs %g\n", (long long)n, r, r % KINDS, top, want);
      }
      if (a[(NB - 1) * R + r] != want_a) {
        ++bad; printf("argmax differs from the host: width %lld row %d kind %d: %d vs %d\n", (long long)n, r, r % KINDS, a[(NB - 1) * R + r], want_a);
      }
      for (int b = 0; b < NB - 1; ++b) {
        uint32_t u0, u1; memcpy(&u0, &m[b * R + r], 4); memcpy(&u1, &m[(NB - 1) * R + r], 4);
        const bool both_nan = m[b * R + r] != m[b * R + r] && top != top;
        if (u0 != u1 && !both_nan) { ++bad; printf("lse max at %d threads differs from 1024: width %lld row %d kind %d: %08x vs %08x\n", blocks[b], (long long)n, r, r % KINDS, u0, u1); }
        if (a[b * R + r] != a[(NB - 1) * R + r]) { ++bad; printf("argmax at %d threads differs from 1024: width %lld row %d kind %d: %d vs %d\n", blocks[b], (long long)n, r, r % KINDS, a[b * R + r], a[(NB - 1) * R + r]); }
      }
    }
    cudaFree(dx); cudaFree(db); cudaFree(dm); cudaFree(da);
  }
  printf("%s argmax_lse_rows: %d rows at %d block sizes (32-1024 threads), %d differences\n", bad ? "FAIL" : "PASS", rows_checked, NB, bad);
  return bad ? 1 : 0;
}
