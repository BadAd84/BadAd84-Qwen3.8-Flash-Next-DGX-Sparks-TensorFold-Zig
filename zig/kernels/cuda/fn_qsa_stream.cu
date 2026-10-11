// Flash Next's indexer block selection (ours): attention._select / _select_tiles' lists from ONE CTA a
// row reading the row's block scores ONCE, keeping a running candidate buffer in shared memory.
//
// The lists are integers fixed by the scores alone: a row keeps its TOP blocks under the order (key descending, block
// id ascending), keys being the fp32 score bits made order-preserving (sign-flipped), and lists them in block order
// (RATIO token ids a block), then the unfinished block's tokens; a row with complete <= TOP stores only its length.
// `_select` finds the cut (the TOP-th largest key) by 33 halvings and takes the ties at the cut lowest id first;
// `_select_tiles` the same cut by radix select. Any exact algorithm gives the same words.
//
// Here the row streams in id order through batches of THREADS * V keys. The buffer (CAP keys and ids, in id order)
// always holds TOPP(P): the TOP best of the processed prefix P under that order, plus possibly more. Why it suffices:
//   - every block of the row's selection S that lies in P is in TOPP(P) (TOP blocks of P ranked above it would rank
//     above it in the whole row too);
//   - a later block x (its id above all of P) enters TOPP(P + x) only if its key is ABOVE the key of TOPP(P)'s last
//     element (a tie at that key loses on the id), so after a compaction to TOPP with cut T, a key <= T is dropped
//     and a key > T appended (a stale T, lower than the current cut, only keeps more);
//   - a compaction of a buffer B with TOPP(P) <= B <= P gives TOPP(B) = TOPP(P).
// When an append would overflow, the buffer is compacted (radix select of the cut over 11, 11 and 10 bits, then the
// keys above it and the first `need` ties at it, kept in order), which raises T; the end compacts once more and the
// TOP survivors, in id order, are the row's list.
#include <cooperative_groups.h>
#include <stdint.h>

namespace tf_qsa_stream {

constexpr int THREADS = 512;
constexpr int WARPS = THREADS / 32;
constexpr int BINS = 2048;
constexpr int BPT = BINS / THREADS;  // bins a thread owns when finding the digit

__device__ __forceinline__ uint32_t key_of(float v) {
  const uint32_t bits = __float_as_uint(v);
  return (bits & 0x80000000u) ? ~bits : (bits | 0x80000000u);
}

// exclusive prefix over threads (thread order) of v; *total the block's sum. Every thread calls it.
__device__ __forceinline__ int excl_scan(int v, int* ws, int* total) {
  const int lane = threadIdx.x & 31, warp = threadIdx.x >> 5;
  int x = v;
#pragma unroll
  for (int o = 1; o < 32; o <<= 1) {
    const int y = __shfl_up_sync(0xffffffffu, x, o);
    if (lane >= o) x += y;
  }
  if (lane == 31) ws[warp] = x;
  __syncthreads();
  if (warp == 0) {
    int w = lane < WARPS ? ws[lane] : 0;
#pragma unroll
    for (int o = 1; o < 32; o <<= 1) {
      const int y = __shfl_up_sync(0xffffffffu, w, o);
      if (lane >= o) w += y;
    }
    if (lane < WARPS) ws[lane] = w;  // inclusive warp sums
  }
  __syncthreads();
  const int before = (warp > 0 ? ws[warp - 1] : 0) + x - v;
  *total = ws[WARPS - 1];
  __syncthreads();  // ws reused by the next call
  return before;
}

struct Shared {
  int hist[BINS];
  int ws[WARPS];
  int cnt[32 * WARPS];  // appends of a batch by (key slot j, warp), then their exclusive offsets
  int bcast[4];
};

// The TOP-th largest of the n buffer keys: *cut, and the ties at it to take (`need`, returned). Radix select over the
// top 11, 11 and 10 bits; every thread returns the same values.
__device__ __forceinline__ int radix_cut(const uint32_t* ck, int n, int top, Shared* sh, uint32_t* cut) {
  const int tid = threadIdx.x, lane = tid & 31;
  uint32_t prefix = 0, pmask = 0;
  int need = top;
#pragma unroll 1
  for (int p = 0; p < 3; ++p) {
    const int shift = p == 0 ? 21 : p == 1 ? 10 : 0;
    const uint32_t dmask = p < 2 ? 0x7FFu : 0x3FFu;
    for (int j = tid; j < BINS; j += THREADS) sh->hist[j] = 0;
    __syncthreads();
    for (int base = 0; base < n; base += THREADS) {
      const int i = base + tid;
      const uint32_t k = i < n ? ck[i] : 0u;
      const bool ok = i < n && (k & pmask) == prefix;
      const int d = ok ? static_cast<int>((k >> shift) & dmask) : -1;
      const unsigned peers = __match_any_sync(0xffffffffu, d);
      if (ok && lane == __ffs(peers) - 1) atomicAdd(&sh->hist[d], __popc(peers));
    }
    __syncthreads();
    // thread t holds bins [BINS - BPT (t + 1), BINS - BPT t): the keys in higher bins are the threads before it
    const int hi = BINS - BPT * tid;
    int local = 0;
#pragma unroll
    for (int q = 1; q <= BPT; ++q) local += sh->hist[hi - q];
    int all;
    int above = excl_scan(local, sh->ws, &all);
#pragma unroll
    for (int q = 1; q <= BPT; ++q) {
      const int d = hi - q;
      const int c = sh->hist[d];
      if (above < need && above + c >= need) {  // the one digit whose keys hold the need-th largest
        sh->bcast[0] = d;
        sh->bcast[1] = need - above;
      }
      above += c;
    }
    __syncthreads();
    const int d = sh->bcast[0];
    need = sh->bcast[1];
    prefix |= static_cast<uint32_t>(d) << shift;
    pmask |= dmask << shift;
    __syncthreads();
  }
  *cut = prefix;
  return need;
}

// The buffer's TOPP, in place and in order: the keys above the cut and the first `need` ties at it. Returns the cut;
// the buffer then holds exactly `top` entries.
template <int KMAX>
__device__ __forceinline__ uint32_t compact(uint32_t* ck, int* cid, int n, int top, Shared* sh) {
  uint32_t cut;
  const int need = radix_cut(ck, n, top, sh, &cut);
  const int tid = threadIdx.x;
  const int K = (n + THREADS - 1) / THREADS;  // <= KMAX
  const int i0 = min(n, tid * K), i1 = min(n, i0 + K);
  uint32_t k[KMAX];
  int id[KMAX];
  int a = 0, e = 0;
#pragma unroll
  for (int q = 0; q < KMAX; ++q) {
    const int i = i0 + q;
    k[q] = i < i1 ? ck[i] : 0u;
    id[q] = i < i1 ? cid[i] : 0;
    a += i < i1 && k[q] > cut;
    e += i < i1 && k[q] == cut;
  }
  int A, E;
  const int a_before = excl_scan(a, sh->ws, &A);  // its barriers also order every read above before the writes
  const int e_before = excl_scan(e, sh->ws, &E);
  int place = a_before + min(e_before, need);
  int eq = e_before;
#pragma unroll
  for (int q = 0; q < KMAX; ++q) {
    const int i = i0 + q;
    if (i >= i1) continue;
    bool chosen = k[q] > cut;
    if (k[q] == cut) {
      chosen = eq < need;
      ++eq;
    }
    if (chosen) {
      ck[place] = k[q];
      cid[place] = id[q];
      ++place;
    }
  }
  __syncthreads();
  return cut;
}

// Streams the keys of blocks [b0, b1) of `row` through the buffer (ids absolute): on return the buffer's first n
// entries, in id order, hold the range's TOPP (all of the range while it has <= top keys, or more). Batches of
// THREADS * V keys; a batch's appends go in id order, after a compaction when they would overflow CAP.
template <int CAP, int V>
__device__ __forceinline__ int stream_range(const float* __restrict__ row, int b0, int b1, int top, uint32_t* ck,
                                            int* cid, Shared* sh) {
  static_assert(CAP % THREADS == 0 && V <= 32, "buffer and batch shapes");
  constexpr int KMAX = CAP / THREADS;
  constexpr int BATCH = THREADS * V;
  const int tid = threadIdx.x, lane = tid & 31, warp = tid >> 5;
  const unsigned lt = (1u << lane) - 1u;
  int n = 0;
  bool have = false;  // a cut T exists (the buffer was compacted once)
  uint32_t T = 0;
  float nxt[V];
#pragma unroll
  for (int j = 0; j < V; ++j) {
    const int i = b0 + j * THREADS + tid;
    nxt[j] = i < b1 ? row[i] : 0.f;
  }
#pragma unroll 1
  for (int base = b0; base < b1; base += BATCH) {
    uint32_t k[V];
#pragma unroll
    for (int j = 0; j < V; ++j) k[j] = key_of(nxt[j]);
    // the next batch's loads in flight while this one is filtered
    const int nb0 = base + BATCH;
#pragma unroll
    for (int j = 0; j < V; ++j) {
      const int i = nb0 + j * THREADS + tid;
      nxt[j] = i < b1 ? row[i] : 0.f;
    }
#pragma unroll 1
    for (int attempt = 0; attempt < 2; ++attempt) {
      unsigned m[V];
      int c = 0;
#pragma unroll
      for (int j = 0; j < V; ++j) {
        const int i = base + j * THREADS + tid;
        const bool f = i < b1 && (!have || k[j] > T);
        m[j] = __ballot_sync(0xffffffffu, f);
        c += f;
      }
      if (!__syncthreads_or(c)) break;
      // appends in id order: (slot j, then thread); per (j, warp) counts, then their exclusive offsets
      if (lane == 0) {
#pragma unroll
        for (int j = 0; j < V; ++j) sh->cnt[j * WARPS + warp] = __popc(m[j]);
      }
      __syncthreads();
      if (warp == 0) {
        int carry = 0;
        for (int q0 = 0; q0 < V * WARPS; q0 += 32) {
          const int v = q0 + lane < V * WARPS ? sh->cnt[q0 + lane] : 0;
          int x = v;
#pragma unroll
          for (int o = 1; o < 32; o <<= 1) {
            const int y = __shfl_up_sync(0xffffffffu, x, o);
            if (lane >= o) x += y;
          }
          if (q0 + lane < V * WARPS) sh->cnt[q0 + lane] = carry + x - v;
          carry += __shfl_sync(0xffffffffu, x, 31);
        }
        if (lane == 0) sh->bcast[2] = carry;
      }
      __syncthreads();
      const int total = sh->bcast[2];
      if (n + total > CAP) {  // first make room: the buffer's TOPP, a higher cut, then the batch again
        T = compact<KMAX>(ck, cid, n, top, sh);
        n = top;
        have = true;
        continue;
      }
#pragma unroll
      for (int j = 0; j < V; ++j) {
        if (m[j] >> lane & 1u) {
          const int pos = n + sh->cnt[j * WARPS + warp] + __popc(m[j] & lt);
          ck[pos] = k[j];
          cid[pos] = base + j * THREADS + tid;
        }
      }
      n += total;
      __syncthreads();
      break;
    }
  }
  return n;
}

// SC [rows, NB] fp32 scores, POS0 the first row's position; IDS [rows, IDW], NKR [rows], SPR [rows]. One CTA a row,
// THREADS threads, dynamic shared memory CAP keys and CAP ids. Needs CAP >= top + THREADS * V.
template <int CAP, int V>
__device__ __forceinline__ void stream_body(const float* __restrict__ SC, const int* __restrict__ POS0,
                                            int* __restrict__ IDS, int* __restrict__ NKR, int* __restrict__ SPR,
                                            int NB, int ratio, int top, int idw) {
  constexpr int KMAX = CAP / THREADS;
  extern __shared__ __align__(16) uint32_t dyn[];
  __shared__ Shared sh;
  uint32_t* ck = dyn;
  int* cid = reinterpret_cast<int*>(dyn + CAP);
  const int r = blockIdx.x;
  const int tid = threadIdx.x;
  const int end = __ldg(POS0) + r + 1;
  const int complete = end / ratio;
  if (complete <= top) {
    if (tid == 0) {
      NKR[r] = end;
      SPR[r] = 0;
    }
    return;
  }
  const float* row = SC + static_cast<size_t>(r) * NB;
  const int n = stream_range<CAP, V>(row, 0, complete, top, ck, cid, &sh);
  compact<KMAX>(ck, cid, n, top, &sh);  // n > top: the whole row passed through (complete > top)
  int* out = IDS + static_cast<size_t>(r) * idw;
  for (int i = tid; i < top * ratio; i += THREADS) out[i] = cid[i / ratio] * ratio + i % ratio;
  if (tid < ratio) {
    const int tail = ratio * complete + tid;
    if (tail < end) out[top * ratio + tid] = tail;
  }
  if (tid == 0) {
    NKR[r] = top * ratio + end - ratio * complete;
    SPR[r] = 1;
  }
}

// The cluster form: C CTAs a row (consecutive), CTA `rank` streams blocks [rank * per, ...) (per = ceil(complete / C))
// into its own buffer and cuts it to its TOPP; rank 0 then gathers the C lists in rank order (= block order) through
// distributed shared memory, cuts the union (TOPP of a union of TOPPs is the row's TOPP) and stores the list.
// Needs CAP >= top + THREADS * V and CAP >= C * top.
template <int C, int CAP, int V>
__device__ __forceinline__ void cstream_body(const float* __restrict__ SC, const int* __restrict__ POS0,
                                             int* __restrict__ IDS, int* __restrict__ NKR, int* __restrict__ SPR,
                                             int NB, int ratio, int top, int idw) {
#if __CUDA_ARCH__ < 900
  __trap();  // clusters need sm_90+: the host never launches this
#else
  constexpr int KMAX = CAP / THREADS;
  extern __shared__ __align__(16) uint32_t dyn[];
  __shared__ Shared sh;
  uint32_t* ck = dyn;
  int* cid = reinterpret_cast<int*>(dyn + CAP);
  cooperative_groups::cluster_group cl = cooperative_groups::this_cluster();
  const int rank = static_cast<int>(cl.block_rank());
  const int r = blockIdx.x / C;
  const int tid = threadIdx.x;
  const int end = __ldg(POS0) + r + 1;
  const int complete = end / ratio;
  if (complete <= top) {  // the whole cluster leaves here (the same row)
    if (rank == 0 && tid == 0) {
      NKR[r] = end;
      SPR[r] = 0;
    }
    return;
  }
  const float* row = SC + static_cast<size_t>(r) * NB;
  const int per = (complete + C - 1) / C;
  const int b0 = min(complete, rank * per), b1 = min(complete, b0 + per);
  int n = stream_range<CAP, V>(row, b0, b1, top, ck, cid, &sh);
  if (n > top) {
    compact<KMAX>(ck, cid, n, top, &sh);
    n = top;
  }
  if (tid == 0) sh.bcast[3] = n;
  cl.sync();  // every CTA's list and length published
  if (rank == 0) {
    int off = n;
#pragma unroll 1
    for (int q = 1; q < C; ++q) {
      const Shared* rs = cl.map_shared_rank(&sh, q);
      const uint32_t* rk = cl.map_shared_rank(ck, q);
      const int* ri = cl.map_shared_rank(cid, q);
      const int nq = rs->bcast[3];
      for (int i = tid; i < nq; i += THREADS) {
        ck[off + i] = rk[i];
        cid[off + i] = ri[i];
      }
      off += nq;
    }
    n = off;
  }
  cl.sync();  // no CTA leaves while rank 0 may still read its buffer
  if (rank != 0) return;
  // n > top: two slices hold keys and every slice gave min(its keys, top) of them
  compact<KMAX>(ck, cid, n, top, &sh);
  int* out = IDS + static_cast<size_t>(r) * idw;
  for (int i = tid; i < top * ratio; i += THREADS) out[i] = cid[i / ratio] * ratio + i % ratio;
  if (tid < ratio) {
    const int tail = ratio * complete + tid;
    if (tail < end) out[top * ratio + tid] = tail;
  }
  if (tid == 0) {
    NKR[r] = top * ratio + end - ratio * complete;
    SPR[r] = 1;
  }
#endif
}

}  // namespace tf_qsa_stream

#define TF_QSA_STREAM(NAME, CAP, V)                                                                                   \
  extern "C" __global__ void __launch_bounds__(tf_qsa_stream::THREADS)                                               \
      NAME(const float* __restrict__ SC, const int* __restrict__ POS0, int* __restrict__ IDS, int* __restrict__ NKR,  \
           int* __restrict__ SPR, int NB, int ratio, int top, int idw) {                                              \
    tf_qsa_stream::stream_body<CAP, V>(SC, POS0, IDS, NKR, SPR, NB, ratio, top, idw);                                 \
  }
TF_QSA_STREAM(fn_qsa_stream_k5v4, 5120, 4)

#define TF_QSA_CSTREAM(NAME, C, CAP, V)                                                                               \
  extern "C" __global__ void __launch_bounds__(tf_qsa_stream::THREADS)                                               \
      NAME(const float* __restrict__ SC, const int* __restrict__ POS0, int* __restrict__ IDS, int* __restrict__ NKR,  \
           int* __restrict__ SPR, int NB, int ratio, int top, int idw) {                                              \
    tf_qsa_stream::cstream_body<C, CAP, V>(SC, POS0, IDS, NKR, SPR, NB, ratio, top, idw);                             \
  }
TF_QSA_CSTREAM(fn_qsa_cstream_c4k4v4, 4, 4096, 4)
