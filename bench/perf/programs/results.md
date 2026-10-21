# Manuscript vs handwritten Go

## Latest: Rust `ms` (2026-10-21)

Median of 7 runs with alternating order; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1 (`-C opt-level=3 -C codegen-units=1`). Checksums and operation counts verified. Ratios are Manuscript time over the other language's time, so below 1.00x is faster than it.

**Read the Rust columns with the caveats.** Manuscript checks Int overflow and list bounds; Go and Rust (release) check only bounds. "Rust, overflow checks" is the same source built with `-C overflow-checks=on`, the closest like-for-like. "folded" means LLVM folded the loop to a constant, so no time is reported; the Go and Manuscript columns still do the work.

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 5.67 | 4.89 | 1.27 | 1.41 | 1.16x | 4.45x | 4.02x |
| read_line | 200000 | 97.09 | 98.30 | 74.52 | 67.86 | 0.99x | 1.30x | 1.43x |
| map_put_get_8k | 16000 | 39.59 | 41.21 | 45.50 | 46.77 | 0.96x | 0.87x | 0.85x |
| int_eq | 10000000 | 1.28 | 1.42 | 0.76 | 1.03 | 0.90x | 1.69x | 1.24x |
| generic_call | 100000000 | 0.75 | 0.80 | 0.77 | 0.85 | 0.94x | 0.98x | 0.88x |
| method_call | 100000000 | 0.93 | 0.88 | 1.69 | 2.14 | 1.06x | 0.55x | 0.43x |
| try | 100000000 | 0.77 | 0.73 | 0.98 | 0.79 | 1.05x | 0.79x | 0.97x |
| match | 100000000 | 3.07 | 2.36 | 1.71 | 2.19 | 1.31x | 1.80x | 1.40x |
| builtin_length | 100000000 | 0.86 | 0.43 | 0.41 | 0.46 | 2.00x | 2.09x | 1.86x |
| for_list | 100000000 | 1.37 | 0.85 | 0.34 | 0.54 | 1.61x | 4.02x | 2.55x |

Manuscript is faster than Go on 4 of 10 rows and within 1.25x on 3 more. match, builtin_length and for_list are 1.3x to 2x slower: Go and LLVM vectorize or fold those loops, and Manuscript has overflow checks, no loop rotation and no hoisting. Rust is faster on most rows, and string_append is 4x faster there. Whole-program kernels: see [`../kernels/README.md`](../kernels/README.md) and [`../competence/README.md`](../competence/README.md).
