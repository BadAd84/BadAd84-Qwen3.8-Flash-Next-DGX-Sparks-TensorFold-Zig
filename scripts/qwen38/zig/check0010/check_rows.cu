// check_rows.cu: patches/0010's two kernels at the new launch width against the shipped ones at 256 threads, bit for
// bit, on adversarial rows. Built against the engine tree (-I to zig/kernels/cuda/torch_ops) twice: NEW includes the
// patched sources, OLD the shipped ones under other names (see run.sh). Exit 0: every row equal.
//
// Rows: random bf16/fp32 values; ties at the first and last column; the maximum in the tail that a 4-wide unrolled
// loop leaves to its remainder loop; -inf rows; +inf; NaN (first wins for argmax); -0/+0 only; widths 248,320 (the
// vocabulary), 79,591 (the draft vocabulary, odd), 1, 7, 4,097 (one past 4 x 1024).
#include <cuda_bf16.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

extern "C" __global__ void tf_argmax_rows_i32_kernel(const void*, int32_t*, int64_t, int64_t, int64_t, int32_t);
extern "C" __global__ void tf_fn_lse_max_kernel(const float*, float*, uint32_t, uint32_t);
extern "C" __global__ void old_lse_max_kernel(const float*, float*, uint32_t, uint32_t);

static uint32_t rng = 12345u;
static uint32_t next() { rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5; return rng; }
static float frand() { return (int32_t(next()) >> 8) * (1.0f / 8388608.0f) * 30.0f; }

static uint16_t bf(float f) { uint32_t u; memcpy(&u, &f, 4); return uint16_t(u >> 16); }

enum Kind { RANDOM, TIE_FIRST, TIE_LAST, TAIL_MAX, NEG_INF, POS_INF, NAN_MID, ZEROS, KINDS };

static void fill(std::vector<float>& r, int kind) {
  const size_t n = r.size();
  for (auto& v : r) v = frand();
  const float big = 1000.f;
  switch (kind) {
    case TIE_FIRST: r[0] = big; r[n / 2] = big; break;
    case TIE_LAST: r[n - 1] = big; if (n > 1) r[n - 2] = big; break;
    case TAIL_MAX: r[n - 1 - (n > 3 ? 2 : 0)] = big; break;
    case NEG_INF: for (auto& v : r) v = -INFINITY; break;
    case POS_INF: r[n / 3] = INFINITY; r[n - 1] = INFINITY; break;
    case NAN_MID: r[n / 2] = NAN; if (n > 2) r[n - 1] = NAN; break;
    case ZEROS: for (size_t i = 0; i < n; ++i) r[i] = (i & 1) ? -0.0f : 0.0f; break;
    default: break;
  }
}

int main() {
  const int64_t widths[] = {248320, 79591, 1, 7, 4097};
  int bad = 0, rows_checked = 0;
  for (int64_t n : widths) {
    const int R = KINDS * 3;
    std::vector<float> h(size_t(R) * n);
    std::vector<uint16_t> hb(h.size());
    for (int r = 0; r < R; ++r) {
      std::vector<float> row(n);
      fill(row, r % KINDS);
      memcpy(&h[size_t(r) * n], row.data(), n * 4);
    }
    for (size_t i = 0; i < h.size(); ++i) hb[i] = bf(h[i]);
    float* dx; uint16_t* db; float *m_old, *m_new; int32_t *a_old, *a_new;
    cudaMalloc(&dx, h.size() * 4); cudaMalloc(&db, hb.size() * 2);
    cudaMalloc(&m_old, R * 4); cudaMalloc(&m_new, R * 4); cudaMalloc(&a_old, R * 4); cudaMalloc(&a_new, R * 4);
    cudaMemcpy(dx, h.data(), h.size() * 4, cudaMemcpyHostToDevice);
    cudaMemcpy(db, hb.data(), hb.size() * 2, cudaMemcpyHostToDevice);
    old_lse_max_kernel<<<R, 256>>>(dx, m_old, R, uint32_t(n));
    tf_fn_lse_max_kernel<<<R, 1024>>>(dx, m_new, R, uint32_t(n));
    tf_argmax_rows_i32_kernel<<<R, 256>>>(db, a_old, R, n, n, 0);
    tf_argmax_rows_i32_kernel<<<R, 1024>>>(db, a_new, R, n, n, 0);
    if (cudaDeviceSynchronize() != cudaSuccess) { printf("FAIL launch at width %lld\n", (long long)n); return 2; }
    std::vector<float> mo(R), mn(R); std::vector<int32_t> ao(R), an(R);
    cudaMemcpy(mo.data(), m_old, R * 4, cudaMemcpyDeviceToHost); cudaMemcpy(mn.data(), m_new, R * 4, cudaMemcpyDeviceToHost);
    cudaMemcpy(ao.data(), a_old, R * 4, cudaMemcpyDeviceToHost); cudaMemcpy(an.data(), a_new, R * 4, cudaMemcpyDeviceToHost);
    for (int r = 0; r < R; ++r) {
      ++rows_checked;
      uint32_t uo, un; memcpy(&uo, &mo[r], 4); memcpy(&un, &mn[r], 4);
      const bool both_nan = mo[r] != mo[r] && mn[r] != mn[r];
      if (uo != un && !both_nan) { ++bad; printf("lse max differs: width %lld row %d kind %d: %08x vs %08x\n", (long long)n, r, r % KINDS, uo, un); }
      if (ao[r] != an[r]) { ++bad; printf("argmax differs: width %lld row %d kind %d: %d vs %d\n", (long long)n, r, r % KINDS, ao[r], an[r]); }
    }
    cudaFree(dx); cudaFree(db); cudaFree(m_old); cudaFree(m_new); cudaFree(a_old); cudaFree(a_new);
  }
  printf("%s check_rows: %d rows, %d differences (lse max 256 vs 1024 threads, argmax 256 vs 1024)\n", bad ? "FAIL" : "PASS", rows_checked, bad);
  return bad ? 1 : 0;
}
