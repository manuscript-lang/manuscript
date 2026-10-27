# Plain list loops

Element-wise loops over `List[T]` (`for i in 0..n: out[i] = ...`) in GFLOPS (one operation per element counts as one flop), higher is better. Four thousand elements per call, so the lists stay in cache; the C versions are the same loops at `-O3` with strict IEEE semantics.

| Kernel | Loop |
| --- | --- |
| `fma32` | `out[i] = a[i] * b[i] + 1.5` over `Float32` |
| `scale64` | `out[i] = a[i] * 2.0` over `Float` |
| `intadd` | `out[i] = a[i] + b[i]` over `Int` (checked add) |
| `stencil` | `out[i] = a[i] + a[i + 1]` |
| `base` | `out[i] = w[base + i] * x[i]` with a loop-invariant `base` |
| `clamp` | `out[i]` is `a[i]` clamped to 0 and 1 |
| `conv` | `out[i] = a[i].to_float() * 0.5` from `Int` to `Float` |
| `dot32` | a `Float32` dot product (a strict-order reduction) |

Run `sh bench/perf/listloops/run.sh 7` (best of N). Compare only runs from the same machine.

## Element addresses as pointer plus offset (2026-10-27)

`claude/project-thread-5wpzrt` on top of 90e401c4; linux/amd64, Intel Xeon at 2.80 GHz (AVX2), four vCPUs, one thread; gcc 13.3.0; LLVM 23.1.1; best of 7 (the `main` column: best of 5, same machine and session).

| Kernel | ms on main | ms | c-sse2 | c-avx2 |
| --- | ---: | ---: | ---: | ---: |
| fma32 | 3.06 | 12.68 | 12.78 | 11.56 |
| scale64 | 1.56 | 5.30 | 3.54 | 3.90 |
| intadd | 1.26 | 1.34 | 2.55 | 2.94 |
| stencil | 1.64 | 4.35 | 3.57 | 6.07 |
| base | 1.63 | 8.61 | 6.48 | 6.06 |
| clamp | 1.48 | 9.91 | 4.25 | 10.87 |
| conv | 1.67 | 3.48 | 1.63 | 2.44 |
| dot32 | 1.65 | 1.66 | 1.66 | 1.67 |

- Release builds emitted every element address as `inttoptr (base + i * size)`; LLVM's loop vectorizer answered "cannot identify array bounds" for each of these loops. Emitting `inttoptr base` plus a `getelementptr` of the scaled index lets it vectorize them (width 4, interleave 2 for `Float32`).
- `intadd` stays scalar: the overflow check is an early exit whose condition LLVM cannot predicate ("Early exit loop with store but no supported condition load").
- `dot32` stays scalar in every language: a strict-order reduction cannot be reassociated without fast-math.
- Loop versioning for bounds checks (one range check before the loop, an unchecked copy behind it) was prototyped and measured: no kernel changed by more than noise, because LLVM already vectorizes loops whose only other exits are `i < len` bounds checks.

## Per-CPU copies of vectorized loops (2026-10-27)

`claude/project-thread-clrilm` on top of 9f41921f; linux/amd64, Intel Xeon at 2.10 GHz (AVX2), four vCPUs, one thread; gcc 13.3.0; LLVM 23.1.1; best of 7, `ms` columns from the same session. "before" is the build without copies, "after" adds an x86-64-v3 (AVX2, FMA) copy of each function that has a loop over list elements with no calls in it, picked at run time by `msrt_cpu_level` (`MS_CPU_LEVEL=baseline` forces the SSE2 copy).

| Kernel | ms before | ms after | c-sse2 | c-avx2 |
| --- | ---: | ---: | ---: | ---: |
| fma32 | 19.55 | 31.23 | 18.04 | 26.04 |
| scale64 | 5.00 | 4.86 | 4.91 | 3.88 |
| intadd | 1.64 | 1.64 | 2.76 | 3.27 |
| stencil | 10.73 | 20.40 | 10.84 | 17.94 |
| base | 10.81 | 18.00 | 9.24 | 15.89 |
| clamp | 10.07 | 17.79 | 4.42 | 8.45 |
| conv | 3.18 | 3.47 | 2.27 | 2.35 |
| dot32 | 2.87 | 2.83 | 2.86 | 2.88 |

- Absolute numbers are higher than the section above because this machine and session differ; compare columns within a table only. With the copies, `ms` is at or above C -O3 AVX2 on every vectorizable kernel here, including `stencil` and `clamp`, where the baseline build trailed it.
- Cost, measured on `bench/perf/stdlib` (a large program): 22 of 1132 functions get a copy; the executable grows from 5.66 MB to 5.78 MB (2%); a release build takes about 21 s against 20 s. Functions with calls in the loop, and loops that do not index lists, get no copy.
- Fault traces: a fault inside the AVX2 copy reports the same frames as the baseline copy (`crates/ms-cli/tests/vectorized_loops.rs`).
- aarch64 and every non-x86-64 target keep one copy; Windows, macOS and Linux x86-64 use the same dispatch.

## Checked `Int` loops: overflow-scan versioning (2026-10-27)

`c/overflow.c`, gcc/clang 18 -O3, same machine; `a[i] + b[i]` over 4096 `int64`, one core, best of 9.

| Loop | SSE2 | AVX2 |
| --- | ---: | ---: |
| checked (early exit on overflow) | 1.53 | 1.45 |
| versioned (overflow scan, then unchecked loop) | 1.80 | 1.73 |
| unchecked | 3.81 | 3.44 |

- Versioning reads every element twice (scan, then add and store), so it cannot pass half the unchecked rate: it gains 17 to 19% over the checked loop, not the 1.5x to 2x that the C reference (2.76 to 3.27) suggests.
- A single pass that stores and ORs the flags would reach the unchecked rate, but it writes `out[i+1..]` before the fault at `i`, which breaks "same stores, same fault". Chunking and rolling back costs the second pass again.
- Decision: not built. A general transformation would need the loop body proved free of side effects other than the stores and `out` proved disjoint from the inputs, for under 20% on one kernel shape.

## Regression guards

- `crates/ms-cli/tests/vectorized_loops.rs` builds an `fma` and a `scale` loop with the LLVM backend and asserts `opt -pass-remarks=loop-vectorize` reports both vectorized. It runs wherever the bundled LLVM tools are available, on every platform CI covers.
- The release workflow runs this suite on the tagged Linux build and keeps the table as the `listloops-<tag>` artifact; compare it with the newest dated section above.
