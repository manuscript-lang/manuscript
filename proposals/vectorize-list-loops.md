# Vectorize plain list loops

## Summary

- Problem: a plain `for i in 0..n: out[i] = a[i] * b[i] + c` over lists runs at 3 GFLOPS where the same C loop runs at 12.8 (SSE2) to 16.6 (AVX2).
- Cause: Release builds hand LLVM every element address as `inttoptr (base + i * size)`. LLVM's loop vectorizer cannot identify the array and gives up.
- Change: emit `inttoptr base` plus a `getelementptr` of the scaled index in `crates/ms-clif/src/llvm_ir.rs`. About 25 lines, no language change, no change to results.
- Cost: none measured; the unit and e2e suites pass. One Release-only code path changes.
- Decision requested: land the address change; skip loop versioning; decide whether `Int` overflow checks need their own proposal.

## Status

Proposal, 2026-10-27, checked against 90e401c4 on `main`.

Direction (from the SIMD thread): let LLVM auto-vectorize plain element-wise list loops with unchanged results, no fast-math, no language changes; reductions stay in `@std/vec`. The thread asked to prototype bounds-check versioning, the counted-loop overflow check and the list-header writeback first, and to measure against C. "Don't merge anything" applies, so this is a branch and a proposal.

## Problem

Measured with `bench/perf/listloops/run.sh` (one core, 4096 elements, best of 5 to 7, same machine and session):

| Kernel | ms on main | C -O3 SSE2 | C -O3 AVX2 |
| --- | ---: | ---: | ---: |
| fma32 `out[i] = a[i] * b[i] + 1.5` | 3.06 | 12.78 | 11.56 |
| scale64 | 1.56 | 3.54 | 3.90 |
| stencil `a[i] + a[i + 1]` | 1.64 | 3.57 | 6.07 |
| base `w[base + i] * x[i]` | 1.63 | 6.48 | 6.06 |

```ms
def fma(a: List[Float32], b: List[Float32], var out: List[Float32], n: Int) -> Unit:
    for i in 0..n:
        out[i] = a[i] * b[i] + 1.5
```

- Verified: `opt -pass-remarks-missed=loop-vectorize` on the emitted IR reports `loop not vectorized: cannot identify array bounds` for these loops.
- Verified: the MIR is already clean. `ms-mir` threads the list through the loop as an SSA value and writes it back once (`put` after the loop), the induction variable's `iadd` is unchecked (`range.rs` bounded counters), and `f32.round` becomes native `float` arithmetic in LLVM.
- Non-goals: reductions (`sum`, `dot`, `max`; they need reassociation), new syntax, fast-math, per-CPU code (the SIMD branch owns that).

## Design

Rule: an address built as `base + product` is emitted as `getelementptr i8, ptr (inttoptr base), i64 product`, not `inttoptr (base + product)`.

- `Tr::binary` records an `iadd` of two `i64` whose second operand is an `imul` or `ishl` result; `Tr::ptr` emits the pair for a memory access through that value.
- No `inbounds`: dropping it measured the same and cannot introduce poison for empty lists or past-the-end pointers.
- Semantics, ownership and faults are untouched: the check still precedes the address computation (`elem_addr` in `ms-clif/src/lower.rs`), and LLVM keeps every early exit.

```text
before: %s = add i64 %base, %off ; %p = inttoptr i64 %s to ptr ; load float, ptr %p
after : %b = inttoptr i64 %base to ptr ; %p = getelementptr i8, ptr %b, i64 %off ; load float, ptr %p
```

Measured result (`bench/perf/listloops/README.md`): fma32 3.06 to 12.68, scale64 1.56 to 5.30, stencil 1.64 to 4.35, base 1.63 to 8.61, clamp 1.48 to 9.91, conv 1.67 to 3.48. Every one is at or above C at the baseline SSE2 level except `intadd` and the strict reduction `dot32`.

## What the requested steps measured

| Step | Finding |
| --- | --- |
| 1. Bounds-check loop versioning | Prototyped as an `ms-mir` pass (guard `n <= len(l) - k`, unchecked copy, original loop as the fault path; about 600 lines, kept at `architecture/auto-vectorize/versioning.rs.txt` in the project files). On 8 kernels it changed nothing beyond noise (fma32 12.65 vs 12.88). LLVM 23 already vectorizes a loop whose other exits are `i < len`. Not proposed. |
| 2. `for i in 0..n` overflow check | Already removed: `range.rs` `ASSUME_BOUNDED_COUNTERS` turns the increment into a plain `iadd` (visible in the optimized MIR). Nothing to do. |
| 3. List header in registers | Not a blocker: lists are SSA values in MIR, written back once. Nothing to do for these loops. |
| 4. `Float32` round-trips | Not a blocker: `fma32` matches C. Nothing to do. |
| 5. AVX2 multiversioning | Later measured and built (2026-10-27): 1.6x to 1.8x on `fma32`, `stencil`, `base` and `clamp` for 2% more code on a large program; see `bench/perf/listloops/README.md`. |

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-clif/src/llvm_ir.rs` | `indexed` map, `is_product`, GEP in `ptr` | unit test `an_element_address_is_a_base_pointer_plus_an_offset`; `cargo test -p ms-clif`; `make e2e` (323 fixtures, Release) |
| `bench/perf/listloops/` | new benchmark and result page | `run.sh` |
| `ms-mir`, `ms-lower`, `ms-check`, `ms-rt`, stdlib, docs | unchanged | |

## Alternatives

- Do nothing: element-wise loops stay 4x to 6x below C; the only fast path is `@std/vec`.
- Loop versioning in MIR: measured above, no gain, 600 lines. Revisit only if an LLVM upgrade or a non-affine-index kernel shows bounds exits blocking vectorization.
- Make `Int` loops vectorizable: `intadd` runs at 1.34 against 2.55 to 2.94 for C because the checked add is an early exit. Measured (2026-10-27, `bench/perf/listloops/README.md`): versioning on an overflow scan gains 17 to 19% over the checked loop in C (1.53 to 1.80 GFLOPS) because the data is read twice; a single storing pass would break "same stores, same fault". Not built.

## Staging and verification

1. Land the address change with the unit test and the benchmark page. Gate: `cargo test -p ms-clif`, `make e2e`, `run.sh` shows no kernel slower than main.
2. Optional, separate proposal: `Int` overflow versioning, only if a user-facing workload needs it.

## Open questions

- None that change user-visible behavior. Recommendation: skip steps 1 to 5 beyond the address change, and leave AVX2 multiversioning to the SIMD branch.
