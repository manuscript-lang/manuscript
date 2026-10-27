# Vector kernels

fp32 matrix-vector products (`y = W x`, the inner loop of language-model inference) in GFLOPS, higher is better. `@std/vec.ms` is compared with C on the same machine.

| Variant | What runs |
| --- | --- |
| `ms-vec` | `Matrix.matvec` from `@std/vec.ms`; the binary picks its AVX2 and FMA copy on this CPU |
| `ms-vec-baseline` | the same binary with `MS_VEC_LEVEL=baseline`, forcing the portable SSE2 copy |
| `ms-scalar` | the same product as a plain Manuscript `while` loop over `List[Float32]` |
| `c-scalar` | a plain C loop, `-O3`, IEEE order |
| `c-lanes` | the same eight-lane, four-accumulator kernel as `@std/vec.ms`, `-O3 -mavx2 -mfma` |
| `c-lanes-sse2` | `c-lanes` without AVX, `-O3` |
| `c-fastmath` | a plain C loop with `-O3 -march=native -ffast-math`, so the compiler reorders freely |

Run `sh bench/perf/vec/run.sh 5` (best of N). Compare only runs from the same machine.

## Latest (2026-10-27)

`claude/project-thread-35f6yg` on top of a8b1d72; linux/amd64, Intel Xeon at 2.80 GHz (AVX2, AVX-512), four cores, one thread; gcc 13.3.0; best of 5, GFLOPS.

| Variant | 288x288 | 768x288 | 4096x4096 |
| --- | ---: | ---: | ---: |
| ms-vec | 20.77 | 20.32 | 3.67 |
| ms-vec-baseline | 14.44 | 13.43 | 3.45 |
| ms-scalar | 0.44 | 0.44 | 0.41 |
| c-lanes (AVX2) | 18.16 | 17.95 | 3.79 |
| c-lanes-sse2 | 9.85 | 9.52 | 3.28 |
| c-fastmath | 15.69 | 15.54 | 3.84 |
| c-scalar | 1.87 | 1.78 | 1.52 |

- The cache-resident sizes run at or above C with the same kernel, and about 47 times the plain Manuscript loop.
- 4096x4096 (64 MB of weights) is bound by memory bandwidth; every vector variant lands near 3.5 to 4 GFLOPS on one core. Using more cores is the next step.
- `ms-vec-baseline` beats `c-lanes-sse2`; the cause has not been investigated.
