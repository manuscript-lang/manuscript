# Manuscript vs handwritten Go

## Latest: Rust `ms` (2026-10-22)

Median of 7 runs with alternating order; linux/amd64, four cores, Go 1.24.7, rustc 1.99.1 (`-C opt-level=3 -C codegen-units=1`). Checksums and operation counts verified. Ratios are Manuscript time over the other language's time, so below 1.00x is faster than it.

**Read the Rust columns with the caveats.** Manuscript checks Int overflow and list bounds; Go and Rust (release) check only bounds. "Rust, overflow checks" is the same source built with `-C overflow-checks=on`, the closest like-for-like. "folded" means LLVM folded the loop to a constant, so no time is reported; the Go and Manuscript columns still do the work.

| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| string_append_50k | 50000 | 6.20 | 4.44 | 1.18 | 1.65 | 1.40x | 5.24x | 3.76x |
| read_line | 200000 | 135.43 | 112.91 | 67.79 | 69.89 | 1.20x | 2.00x | 1.94x |
| map_put_get_8k | 16000 | 41.19 | 40.09 | 45.24 | 60.43 | 1.03x | 0.91x | 0.68x |
| int_eq | 10000000 | 0.84 | 1.30 | 1.06 | 1.05 | 0.64x | 0.79x | 0.80x |
| generic_call | 100000000 | 0.63 | 0.69 | 0.50 | 0.55 | 0.91x | 1.27x | 1.16x |
| method_call | 100000000 | 0.00 | 2.30 | 1.82 | 2.07 | 0.00x | 0.00x | 0.00x |
| try | 100000000 | 0.66 | 0.80 | 0.73 | 0.79 | 0.83x | 0.92x | 0.84x |
| match | 100000000 | 1.69 | 2.17 | 1.71 | 1.89 | 0.78x | 0.99x | 0.90x |
| builtin_length | 100000000 | 0.00 | 0.32 | 0.35 | 0.33 | 0.00x | 0.00x | 0.00x |
| for_list | 100000000 | 0.52 | 1.06 | 0.30 | 0.51 | 0.49x | 1.75x | 1.02x |

Release builds use LLVM (bundled `opt`/`llc`, `-O3`). Manuscript is faster than Go on 7 of 10 rows (method_call and builtin_length fold to constants), ties on map_put_get and is slower on string_append (1.4x) and read_line (1.2x). Against Rust with overflow checks it is slower on string_append (3.8x: a call per append against an inlined push), read_line (1.9x) and generic_call (1.2x), and level or ahead elsewhere; for_list is level with checks on. Whole-program kernels: see [`../kernels/README.md`](../kernels/README.md) and [`../competence/README.md`](../competence/README.md).
