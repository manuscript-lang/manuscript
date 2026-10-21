# Whole-program kernels

`programs/` measures one operation per loop and several of its results come from proofs that fit those exact loops. These kernels are ordinary programs written the way a user would write them (no attempt to match a compiler proof), each compared with hand-written Go that uses a slice, struct or map directly. Every sample must report the same checksum. Reproduce with `MS=./ms sh bench/perf/kernels/run.sh 5`; compare only runs from the same machine.

Reference run of the Rust `ms` after #929 (2026-10-21; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1; median of 7, microseconds). "Rust" is the same algorithms hand-written with `Vec`/`HashMap` at `opt-level=3`; "Rust, overflow checks" adds `-C overflow-checks=on`. Ratios are Manuscript over the other language.

| kernel | go us | ms us | ms / go | rust us | rust / go | rust-checked us | rust-checked / go | ms / rust | ms / rust-checked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 65103 | 34489 | 0.53x | 28759 | 0.44x | 31085 | 0.48x | 1.20x | 1.11x |
| nbody_200k | 10669 | 12798 | 1.20x | 7215 | 0.68x | 7193 | 0.67x | 1.77x | 1.78x |
| life_128x128_50 | 59680 | 25339 | 0.42x | 3682 | 0.06x | 3821 | 0.06x | 6.88x | 6.63x |
| matmul_200 | 12589 | 24130 | 1.92x | 7775 | 0.62x | 8141 | 0.65x | 3.10x | 2.96x |
| trees_d16_x20 | 47521 | 52737 | 1.11x | 33392 | 0.70x | 35932 | 0.76x | 1.58x | 1.47x |
| collatz_1M | 306569 | 443024 | 1.45x | 191533 | 0.62x | 304039 | 0.99x | 2.31x | 1.46x |
| map_count_2M | 27199 | 36135 | 1.33x | 26064 | 0.96x | 27717 | 1.02x | 1.39x | 1.30x |

Manuscript is faster than hand-written Go on sieve and life, and between 1.1x and 1.9x slower on the rest (matmul worst). It is 1.1x to 1.8x slower than Rust with overflow checks on sieve, nbody, trees, collatz and map_count, and 3x to 6.6x slower on matmul and life, where LLVM vectorizes. The sections below were measured on the earlier Go backend and are kept for the cost analysis, not as current numbers.

## Where the remaining time goes

Measured by editing the emitted Go (`ms emit`) and rebuilding; each change is independent and the numbers are relative to the same unedited build.

| Cost | Evidence | Applies to |
|---|---|---|
| Checked Int `+ - *` | removing the checks alone: collatz 1.45x, life 1.45x, sieve 1.2x | Int loops, indexes, counters |
| Cancellation poll in every loop | removing the polls alone: collatz 1.2x, life 1.1x | every loop |
| `List.Items` reloaded through the list pointer | caching the slice header in registers: matmul 1.5x, sieve 1.15x, nbody 1.1x | indexed list loops |
| Ordered Map | map_count 1.65x over `map[int]int` even with the closed Int map proof | every non-proved Map |
| Recursive sum types | each `Node` boxes two interface fields, 32 bytes against 16 for a hand pointer node, plus `Enter`/`Exit` depth counting | trees |

Literal-operand specializations of the checked helpers (`x + 1`, `3 * x`) were tried and measured no faster.

## C baselines for a no-GC backend

`c/plain.c` is the hand-written C ceiling: the same algorithms, inline structs, exact allocations, an unordered map, no checks. `c/ms.c` is the C a no-GC backend would emit from `ms/src/main.ms` under value semantics: unique ownership with deterministic frees, inline record storage, growable lists, an insertion-ordered compact map, null-niche boxed `Tree`, and the current runtime contract (checked Int, bounds-checked lists, a relaxed atomic cancellation load on every loop back edge). `nbody` indexes per access because two `mut` borrows into one list violate exclusivity. `ABLATE=1` adds `c-ms` builds with one check compiled out each (`-DMS_NO_POLL`, `-DMS_NO_OVERFLOW`, `-DMS_NO_BOUNDS`, or all three). Reproduce with `CC=clang ABLATE=1 MS=./ms sh bench/perf/kernels/run.sh 9`.

Run on 2026-10-19 (Go 1.25.0, clang 18.1.3 `-O2`, linux/amd64 Xeon 2.1 GHz, four vCPUs, min of 9, microseconds, ratio to hand-written Go):

| kernel | Go | Manuscript (Go backend) | C | C, Manuscript semantics | no poll | no overflow checks | no bounds checks | unchecked |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| sieve_5M | 73140 | 1.52x | 0.34x | 0.43x | 0.43x | 0.38x | 0.40x | 0.35x |
| nbody_200k | 10301 | 1.09x | 0.91x | 0.96x | 0.95x | 0.97x | 0.94x | 0.93x |
| life_128x128_50 | 61385 | 1.31x | 0.09x | 0.54x | 0.52x | 0.14x | 0.50x | 0.08x |
| matmul_200 | 12489 | 1.82x | 0.32x | 0.57x | 0.56x | 0.60x | 0.43x | 0.44x |
| trees_d16_x20 | 46185 | 1.75x | 0.70x | 0.74x | 0.74x | 0.67x | 0.68x | 0.67x |
| collatz_1M | 303162 | 1.50x | 0.61x | 0.97x | 0.95x | 0.59x | 0.94x | 0.58x |
| map_count_2M | 25695 | 1.37x | 0.35x | 0.64x | 0.61x | 0.50x | 0.74x | 0.84x |

- Manuscript semantics in C beat hand-written Go on every kernel (0.43x–0.97x) and are 1.1x–3.5x faster than the current Go backend.
- Overflow checks are the dominant remaining cost: life 3.8x and collatz 1.6x slower than with them removed. In life every check guards index arithmetic with known ranges (`x + dx` for `dx` in -1..1), so range analysis in the backend could remove them; collatz's `3 * x + 1` can overflow and needs its check.
- Bounds checks cost matmul 1.3x (nested `List[List[Float]]` indexing); hoisting them out of the `k` loop is the fix.
- The cancellation poll is nearly free as a relaxed load: at most 5%, within run-to-run noise.
- Unique ownership with malloc/free is not the bottleneck: trees runs at the hand-written C ceiling.
- map_count's gap to C is the source's two lookups (`get` then `add`) and the ordered map, not checks; its unchecked build is consistently slower, which looks like a code-layout effect and should not be read as checks helping.
