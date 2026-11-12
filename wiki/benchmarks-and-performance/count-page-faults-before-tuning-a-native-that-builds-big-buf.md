[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Count page faults before tuning a native that builds big buffers

Verified (2026-10-24, `bench/perf/json`): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts. The Linux `ru_minflt` of the process grew by about 270 faults per call (the size of the document's vectors), because `StdHeap::dealloc` handed every non-arena block to musl's `free`, which unmaps it, while `alloc` took large blocks from the runtime's cache.

Apply when: a native that allocates blocks of hundreds of KiB per call is slower than the same code run in a Rust test.
Evidence: [std heap](../../crates/ms-rt/src/alloc.rs), [JSON benchmark](../../bench/perf/json/README.md).
Verify: `getrusage(RUSAGE_CHILDREN).ru_minflt` for a one-second run of `ms run bench/perf/json/ms.toml -- twitter:doc` stays within a few thousand, not hundreds of thousands.

Verified (2026-11-12, c16-maze-bfs): the heap reservation and grow area are `madvise(MADV_HUGEPAGE)` (`sys::prefer_huge_pages`); minor faults fell 25,200 to 12,000 and wall time 103 to 86 ms, a hello program unchanged in memory. Advising the whole reservation added about 0.35 ms to every program's startup (hello world 1.03 to 1.42 ms: the first touch clears a 2 MiB page), so advice starts 4 MiB in (`HUGE_AFTER`) and a short program never sees a huge page. Measure startup of a hello program, not only faults and RSS, before advising a region. THP is in `madvise` mode on typical hosts, so only advised regions get huge pages; stacks keep `MADV_NOHUGEPAGE`.

Checked (2026-11-12, #3710): there is no macOS or Windows counterpart to `MADV_HUGEPAGE` for the heap reservation. macOS superpages are Intel-only, wired and contiguous (unusable for a 256 GiB lazy reservation) and Apple Silicon has 16 KiB base pages; Windows `MEM_LARGE_PAGES` needs `SeLockMemoryPrivilege` and is not demand-committed. Both stay no-ops; reduce faults there by reusing memory, not by advice. `HUGE_AFTER` is two 2 MiB pages.
