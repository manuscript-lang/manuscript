# Vector kernels

fp32 matrix-vector products (`y = W x`, the inner loop of language-model inference) in GFLOPS, higher is better. `@std/vec.ms` is compared with C on the same machine.

| Variant | What runs |
| --- | --- |
| `ms-vec` | `Matrix.matvec` from `@std/vec.ms`; the binary picks its AVX2 and FMA copy on this CPU |
| `ms-vec-1thread` | the same binary with `MS_VEC_THREADS=1`, on one core |
| `ms-vec-baseline` | the same binary with `MS_VEC_LEVEL=baseline`, forcing the portable SSE2 copy |
| `ms-scalar` | the same product as a plain Manuscript `while` loop over `List[Float32]` |
| `c-scalar` | a plain C loop, `-O3`, IEEE order |
| `c-lanes` | the same eight-lane, four-accumulator kernel as `@std/vec.ms`, `-O3 -mavx2 -mfma` |
| `c-lanes-omp` | `c-lanes` with OpenMP splitting the rows across cores above the same size as `ms-vec` |
| `c-lanes-sse2` | `c-lanes` without AVX, `-O3` |
| `c-fastmath` | a plain C loop with `-O3 -march=native -ffast-math`, so the compiler reorders freely |

Run `sh bench/perf/vec/run.sh 5` (best of N). Compare only runs from the same machine. The C variants other than `c-lanes-omp` run on one core.

## Multiple cores (2026-10-27)

Same machine as below; `matvec` now splits rows across the runtime's compute pool above 262,144 multiply-adds, so 288x288 and 768x288 stay on one core. Best of 5, GFLOPS.

| Variant | 288x288 | 768x288 | 1024x1024 | 4096x4096 |
| --- | ---: | ---: | ---: | ---: |
| ms-vec (4 cores) | 17.59 | 17.61 | 29.27 | 12.84 |
| c-lanes-omp (4 cores) | 17.39 | 16.73 | 32.77 | 12.87 |
| ms-vec-1thread | 18.79 | 17.23 | 11.02 | 3.83 |
| c-lanes (1 core) | 18.68 | 17.35 | 11.30 | 3.72 |
| ms-vec-baseline (4 cores) | 14.52 | 14.15 | 18.92 | 11.42 |
| c-fastmath (1 core) | 15.35 | 15.33 | 11.81 | 4.09 |
| c-scalar | 1.81 | 1.86 | 1.63 | 1.52 |
| ms-scalar | 0.45 | 0.45 | 0.43 | 0.42 |

- Four cores give 2.7x at 1024x1024 and 3.4x at 4096x4096, level with OpenMP running the same kernel.
- The small sizes differ only by run-to-run noise (about 7% here); they take the same one-core path.

## One core (2026-10-27)

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
