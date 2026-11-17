[Wiki](../index.md) › [Benchmarks and performance](index.md) › A block above the cached range asks for huge pages

# A block above the cached range asks for huge pages

A block above `LARGE_MAX` (16 MiB) comes from the system allocator, whose fresh pages cost one page fault per 4 KiB. On the maze workload (c16: a 3 MB grid held as `List[List[String]]`, 48 MiB once flattened) that was 13,000 faults and 21 to 27 ms of system time, about 2 µs each on this VM, against 6,500 faults for Rust's 4-byte chars. `alloc_large` now advises `MADV_HUGEPAGE` over the whole 2 MiB units inside such a block (`advise_huge`), the same advice the heap reservation already uses. Faults fell to 2,300 and wall time from 86 to 73 ms.

- Linux only; macOS and Windows have no usable advice (the existing `prefer_huge_pages` no-op, #3710). That is intended: [parity is functional](platform-parity-means-functional-parity.md).
- Blocks up to 16 MiB are unchanged: they are cached and reused, so they do not pay the fault again.
- Remaining c16 gap (73 against 29 ms) is user time: 345M instructions against 223M, from 16-byte `String` cells where Rust has 4-byte chars.
