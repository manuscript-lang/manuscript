# LLM inference in Manuscript

## Summary

- Goal: CPU inference of llama-family models (llama2.c, then GGUF with quantized weights) in Manuscript, fast enough to matter.
- Measured today: a Float32 matrix-vector product runs at 0.43 GFLOPS, 4x slower than scalar C and about 34x slower than C with SIMD (14.5 GFLOPS), 46x slower than SIMD on four threads (19.9).
- Language gaps are small. Throughput gaps are three: Float32 arithmetic cost, no vectorization (strict FP order), and no zero-copy weights or shared-memory threads.
- Recommendation: do not write kernels in Rust-per-model. Add a few general primitives (Stage 1 to 3 below) and keep the model code (tokenizer, attention, sampling, KV cache, GGUF parsing) in `.ms`.
- Decision requested: approve Stage 1 (Float32 cost and a reassociating reduction) as the first measured step.

## Status

Spike, 2026-10-27, against `0284e42`. Stage 1 Float32 register class implemented (below); the rest is not implemented.

Stage 1a result, 2026-10-27, same machine and benchmark: `Float32` now lives in an f32 register in Cranelift and LLVM codegen (native boundaries still pass `f64`). Matvec on `List[Float32]` went from 0.43 to 3.7 to 4.0 GFLOPS at 768x288 (Float64 1.64, scalar C 1.84) and from 0.42 to 1.4 to 2.0 GFLOPS at 4096x4096 (three runs each, noisy). Reductions remain strictly ordered, so SIMD still needs the general design. Benchmark sources: `architecture/inference-spike/` in the project files (`matvec_f32.ms`, `matvec.c`, `dot_kernel.c`).

## What exists

- `Float32`, `List[Float32]` stored packed (4 bytes per element), `Bytes.float32_le` readers and `append_float32_le` writers (`stdlib/bytes.ms`).
- `exp`, `sqrt`, `pow`, `cos`, `sin` on `Float` (`stdlib/math.ms`).
- `WorkerGroup`: OS threads with separate isolates, 3.95x on four cores for CPU-bound jobs; messages are JSON or raw `Bytes` copies (`stdlib/workers.ms`).
- `Shared[T]` with lock; file `read_at` and `read_vectors` (`stdlib/fs.ms`).
- Strings, maps and JSON for tokenizer vocab and GGUF metadata.

## Measurements

linux/amd64, four cores with AVX2/AVX-512, `ms` release build. Matrix-vector `out = W x`, fp32, W row-major, 768x288 (L2-resident) ×3000 and 4096x4096 (64 MB) ×20. GFLOPS = 2·d·n / time.

| variant | 768x288 | 4096x4096 |
| --- | ---: | ---: |
| Manuscript `List[Float32]`, index loops | 0.43 | 0.42 |
| Manuscript `List[Float]` (f64) | 1.64 | 1.23 |
| C `-O3` (strict FP, scalar) | 1.84 | 1.53 |
| C `-O3 -march=native -ffast-math` (SIMD) | 14.48 | 4.04 |
| same, OpenMP 4 threads | 19.88 | 15.35 |

Reading:

- Float32 is 4x slower than Float64 in Manuscript. Registers hold `f64` and every `Float32` op is followed by an `f32.round` (`proposals/sized-numeric-types.md`), plus a widen on each load. Float64 already matches scalar C.
- C only gets from 1.8 to 14.5 GFLOPS by reassociating the sum (`-ffast-math`). Manuscript, like strict C, must keep left-to-right order, so no backend can vectorize `acc += w[i] * x[j]`.
- At 4096x4096 the single-thread SIMD number (4.0) is memory-bound; four threads reach 15.4 GFLOPS (about 30 GB/s of weights). Real token generation is this case: every token reads every weight once.
- A user `extern def` cannot take a `List` or `Bytes` (`checker.rs:1197`, only Int, Float, Bool, String), so the SIMD kernel cannot be linked in via `--link` today. I did not patch the runtime for the spike.

Tokens per second implied (stories15M ≈ 30 MFLOP/token, fp32, compute-bound): today ≈ 14, Float64-speed ≈ 55, SIMD one thread ≈ 480, SIMD four threads ≈ 600 or more. Larger models are bandwidth-bound: 7B at 4-bit is about 4 GB per token, so about 5 to 8 tokens/s on this machine regardless of language, once the kernel is vectorized and weights are mapped, not copied.

## Gaps and minimal general primitives

1. **Float32 cost.** Keep Float32 in an f32 register class in Cranelift and LLVM instead of f64 plus rounding. Pure compiler change; no language change. Expected: Float32 at or above Float64 speed.
2. **Vectorizable reductions.** Add `List[Float32].dot(other, start, other_start, count)` and the same for `Float`, defined as "sum in unspecified order", implemented as one runtime kernel using SIMD (Rust `std::arch` with runtime feature detection; AVX2/FMA, AVX-512, NEON). A general `dot`/`axpy`/`sum` set serves any numeric program, not only LLMs. Rejected alternative: a `-ffast-math` mode, which changes the meaning of all arithmetic.
3. **Quantized dot products.** `Int8` lists already pack. Add `dot` for `Int8` x `Int8` with `Int32` accumulation (VNNI/dot-product where available), and scalar block-dequant (Q4_0, Q8_0) written in `.ms` over `Bytes`. Needed for 4-bit llama.cpp-class models.
4. **Zero-copy weights.** `fs.map(path) -> Mapped` giving a read-only `Bytes` view with typed accessors (`float32_le` exists), no copy; page cache backs it. Without this a 4 GB model costs a 4 GB read and 4 GB RSS per process.
5. **Shared-memory parallel loops.** Workers share nothing and copy messages, so row-parallel matvec cannot split one `Mapped` weight across threads. Options: (a) `parallel_for(n, chunk, body)` primitive over a read-only mapped view plus an output buffer partitioned per worker; (b) let a mapped read-only `Bytes` be sent to workers by handle. (b) is smaller and general. Latency matters: a token does about 7 matvecs per layer × 6 layers (stories15M), so each fork/join must cost microseconds, which means a persistent worker pool with spin or futex wake, not a JSON message.
6. **Smaller items.** `exp`/`sqrt` on `Float32` without a round trip; `argmax`/`top_k` helpers; a `Bytes` view type with sub-slicing without copying (`Bytes.slice` returns a Result today; confirm it is zero-copy); `Float16`/`BFloat16` as storage-only types with conversion in the dot kernel.

## Staged plan

| stage | work | result | estimate |
| --- | --- | --- | --- |
| 0 | Port llama2.c (fp32 `.bin` checkpoint, BPE tokenizer, RoPE, attention, KV cache, sampler) as `.ms` with `List[Float32]`, no new primitives. Correctness check against llama2.c output with temperature 0 | works at about 14 tok/s on stories15M | 3 to 5 days |
| 1 | Float32 register class; `dot`/`axpy`/`sum` kernels with runtime CPU dispatch | 25 to 40x on matvec single thread | 1 to 2 weeks |
| 2 | `fs.map` read-only mapping, typed views, `Float16` storage | 7B-class files load instantly, RSS = page cache | 1 week |
| 3 | Persistent parallel-for over shared read-only views | 4 threads, bandwidth-bound | 1 to 2 weeks |
| 4 | `Int8` dot with `Int32` accumulate; Q4_0/Q8_0 in `.ms`; GGUF reader in `.ms` | llama.cpp-style quantized models | 2 weeks |
| 5 | Optional: batched prefill (matmul, tiling), speculative sampling, a `@std/tensor.ms` layer | prompt processing speed | open ended |

Stages 1 and 2 are independent and each is useful outside LLMs. Stage 0 is the check that the language is otherwise sufficient and gives the baseline for the rest.

## Not recommended

- GPU/Metal backends: out of scope; the native-boundary rule (Int, Float, Bool, String) and the one-runtime design make this a separate project.
- ONNX runtime or operator-graph execution: an op-graph interpreter would be a second execution model. A GGUF reader plus hand-written llama-family forward pass in `.ms` is smaller and faster to the same models. Revisit only if non-transformer models are a goal.
- Linking llama.cpp: against the Manuscript-first rule.

## Risks

- `dot` with unspecified order makes results differ between CPUs; define the order per implementation and test with tolerances, not equality.
- Spin-waiting pools burn CPU when idle; park after a short spin.
- Quantized kernels are where llama.cpp spends years; expect to reach perhaps 60 to 80% of it, not parity, in Stage 4.
