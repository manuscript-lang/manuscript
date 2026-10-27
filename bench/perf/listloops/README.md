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
