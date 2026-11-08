[Wiki](../index.md) › [Runtime](index.md)

# The cancel sweep cancels each test at every park

Verified: `make cancel-sweep` (`tools/cancel-sweep.ms`) reruns each `tests/e2e/testdata/stdlib` test with `MS_CANCEL_AT_PARK=k` for every park k, on the `stats` runtime, and fails when a cancelled run ends with more live `ms-rt` blocks than the uncancelled run. 182 of 191 fixtures, 17,088 runs, were clean on 2026-11-08.

Limit: it sees `ms-rt` blocks, not Rust-heap or fd leaks in native code; those need a `heap_used` or `/proc/<pid>/fd` fixture ([guard exits](runtime-guard-exits-skip-native-rust-destructors.md)). Park counts are per process and include scheduler threads, so a threaded test can vary.

Apply when: adding a park, a cleanup, or an `rt::Parked`; run the sweep on the touched fixture (`ms run tools/cancel-sweep.ms -- <file>`).

Found by the first sweep: `http-hardening.ms` "close cancels a handler parked on a request body" ends with one 16 B block even with no cancellation (a client read after the server closed the connection triggers it); the sweep compares against that baseline, and `make leak-check` owns the fix.
