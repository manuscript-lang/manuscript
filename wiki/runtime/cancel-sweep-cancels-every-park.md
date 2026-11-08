[Wiki](../index.md) › [Runtime](index.md)

# The cancel sweep cancels each test at every park

Verified: `make cancel-sweep` (`tools/cancel-sweep.ms`) reruns each `tests/e2e/testdata/stdlib` test with `MS_CANCEL_AT_PARK=k` for every park k, on the `stats` runtime, and fails when a cancelled run ends with more live `ms-rt` blocks than the uncancelled run. On 2026-11-08 all 191 fixtures were clean at up to 16 parks each.

The counting runtime also counts Rust's own heap (`ms-rt rust heap at exit: blocks=N`; the std heap is the system allocator there), and the sweep lists a cancelled run that ends with more Rust blocks than the uncancelled one as `heap:` (not a failure: a cancelled test keeps its failure report, so a hit needs triage), which is how `Parked`-class leaks in native code show ([guard exits](runtime-guard-exits-skip-native-rust-destructors.md)). It cannot see fd leaks; count `/proc/<pid>/fd` for those. Park counts are per process and include scheduler threads, so a threaded test can vary.

Apply when: adding a park, a cleanup, or an `rt::Parked`; run the sweep on the touched fixture (`ms run tools/cancel-sweep.ms -- <file>`).

Found by the first sweep (baseline, not cancellation): `http-hardening.ms` "close cancels a handler parked on a request body" ends with one 16 B block even with no cancellation (a client read after the server closed the connection triggers it); the sweep compares against that baseline, and `make leak-check` owned the fix (#3083, covered by the MIR unwind pass).
