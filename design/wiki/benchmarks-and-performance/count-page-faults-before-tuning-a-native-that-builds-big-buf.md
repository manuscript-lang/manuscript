[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Count page faults before tuning a native that builds big buffers

Verified (2026-10-24, `bench/perf/json`): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts. The Linux `ru_minflt` of the process grew by about 270 faults per call (the size of the document's vectors), because `StdHeap::dealloc` handed every non-arena block to musl's `free`, which unmaps it, while `alloc` took large blocks from the runtime's cache.

Apply when: a native that allocates blocks of hundreds of KiB per call is slower than the same code run in a Rust test.
Evidence: std heap, [JSON benchmark](../../../bench/perf/json/README.md).
Verify: `getrusage(RUSAGE_CHILDREN).ru_minflt` for a one-second run of `ms run bench/perf/json/ms.toml -- twitter:doc` stays within a few thousand, not hundreds of thousands.

Verified (2026-11-12, c16-maze-bfs): the heap reservation and grow area are `madvise(MADV_HUGEPAGE)` (`sys::prefer_huge_pages`); minor faults fell 25,200 to 12,000 and wall time 103 to 86 ms, a hello program unchanged in memory. Advising the whole reservation added about 0.35 ms to every program's startup (hello world 1.03 to 1.42 ms: the first touch clears a 2 MiB page), so advice starts 4 MiB in (`HUGE_AFTER`) and a short program never sees a huge page. Measure startup of a hello program, not only faults and RSS, before advising a region. THP is in `madvise` mode on typical hosts, so only advised regions get huge pages; stacks keep `MADV_NOHUGEPAGE`.

Checked (2026-11-12, #3710): there is no macOS or Windows counterpart to `MADV_HUGEPAGE` for the heap reservation. macOS superpages are Intel-only, wired and contiguous (unusable for a 256 GiB lazy reservation) and Apple Silicon has 16 KiB base pages; Windows `MEM_LARGE_PAGES` needs `SeLockMemoryPrivilege` and is not demand-committed. Both stay no-ops; reduce faults there by reusing memory, not by advice. `HUGE_AFTER` is two 2 MiB pages.

Windows, measured (2026-11-16, #3646, `windows-2025` runner): `AdjustTokenPrivileges` for `SeLockMemoryPrivilege` reports 1300 (not held) and `VirtualAlloc(MEM_LARGE_PAGES)` fails with 1314 even for the runner's administrator, so large pages are not available to a normal program. Committing 256 MiB in one `VirtualAlloc` took 129 faults; touching it took 65,536 faults and 22.7 ms, about 0.35 us per 4 KiB fault. Committing in larger chunks therefore changes nothing (the fault is per touched page, not per commit), and the 12,000 faults Linux huge pages saved on `c16-maze-bfs` would cost about 4 ms on Windows. Closed #3646 as not possible; the no-op stays as the platform's half of the `sys` interface.
