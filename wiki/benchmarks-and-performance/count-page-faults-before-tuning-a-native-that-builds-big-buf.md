[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Count page faults before tuning a native that builds big buffers

Verified (2026-10-24, `bench/perf/json`): building a parsed JSON document ran 2x slower through `ms` than in a Rust test of the same code, with identical instruction counts. The Linux `ru_minflt` of the process grew by about 270 faults per call (the size of the document's vectors), because `StdHeap::dealloc` handed every non-arena block to musl's `free`, which unmaps it, while `alloc` took large blocks from the runtime's cache.

Apply when: a native that allocates blocks of hundreds of KiB per call is slower than the same code run in a Rust test.
Evidence: [std heap](../../crates/ms-rt/src/alloc.rs), [JSON benchmark](../../bench/perf/json/README.md).
Verify: `getrusage(RUSAGE_CHILDREN).ru_minflt` for a one-second run of `ms run bench/perf/json/ms.toml -- twitter:doc` stays within a few thousand, not hundreds of thousands.
