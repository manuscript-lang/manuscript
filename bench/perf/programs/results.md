# Manuscript vs handwritten Go

## Latest: Rust `ms` (2026-10-21)

Median of 7 runs with alternating order; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1 (`-C opt-level=3 -C codegen-units=1`). Checksums and operation counts verified. Ratios are Manuscript time over the other language's time, so below 1.00x is faster than it.

**Read the Rust columns with the caveats.** Manuscript checks Int overflow and list bounds; Go and Rust (release) check only bounds. "Rust, overflow checks" is the same source built with `-C overflow-checks=on`, the closest like-for-like. "folded" means LLVM folded the loop to a constant, so no time is reported; the Go and Manuscript columns still do the work.

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 5.99 | 6.32 | 1.50 | 1.41 | 0.95x | 4.00x | 4.24x |
| read_line | 200000 | 104.67 | 145.37 | 76.93 | 85.30 | 0.72x | 1.36x | 1.23x |
| map_put_get_8k | 16000 | 52.99 | 69.74 | 58.19 | 64.05 | 0.76x | 0.91x | 0.83x |
| int_eq | 10000000 | 1.35 | 1.35 | 1.12 | 0.99 | 1.00x | 1.20x | 1.37x |
| generic_call | 100000000 | 0.52 | 0.68 | 0.70 | 0.66 | 0.77x | 0.75x | 0.79x |
| method_call | 100000000 | 0.00 | 1.64 | 1.62 | 2.09 | 0.00x | 0.00x | 0.00x |
| try | 100000000 | 0.34 | 0.68 | 1.34 | 1.00 | 0.50x | 0.25x | 0.34x |
| match | 100000000 | 2.23 | 2.56 | 2.36 | 2.22 | 0.87x | 0.95x | 1.01x |
| builtin_length | 100000000 | 0.00 | 0.33 | 0.38 | 0.40 | 0.00x | 0.00x | 0.00x |
| for_list | 100000000 | 0.62 | 0.84 | 0.38 | 0.74 | 0.74x | 1.64x | 0.84x |

Release builds use LLVM (bundled `opt`/`llc`, `-O3`). Manuscript is faster than Go on 9 of 10 rows (method_call and builtin_length fold to constants) and ties on int_eq. Against Rust with overflow checks it is slower on string_append (4.2x: a call per append against an inlined push), int_eq (1.4x) and read_line (1.2x). Whole-program kernels: see [`../kernels/README.md`](../kernels/README.md) and [`../competence/README.md`](../competence/README.md).
