[Wiki](../index.md) › [Runtime](index.md)

# Number-to-text is a C kernel (`runtime/core/fmt.c`) that Rust reaches through shims

Verified (2026-11-20, Linux x86-64): decimal and radix integers, shortest `Float` and `Float32` text, and the `to_precision`, `to_exponential` and `to_fixed` forms write into a caller's buffer in C and allocate nothing; the string natives (which build the `StrVal` with the Rust allocator) call them through `num.rs` helpers while `msrt_fmt_*` is listed in `runtime/symbols/fmt.txt`. The Rust bodies stay for plain `cargo test` until `ms-rt` is deleted; fix a formatting bug in C, never in the Rust copy. The precision forms use an exact base-1e9 expansion (`c * 5^-q`, rounded half to even), not `snprintf`, because `core` includes no libc header and mingw's printf is not exact. The C and Rust output was compared on 13.5M generated lines and 138M binary32 patterns; `runtime/tests/core_fmt.c` keeps golden values and checks reading back and printf agreement. The power-of-ten table is generated: `ms run tools/float-table.ms -- c > runtime/core/float_table.h`.

Apply when: changing number formatting, moving the string allocator to C (the allocating `msrt_*_to_string` wrappers can then move too), or deleting `ms-rt`.
