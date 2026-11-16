[Wiki](../index.md) › [Runtime](index.md)

# The cancel sweep cancels each test at every park

Verified: `make cancel-sweep` (`tools/cancel-sweep.ms`) reruns each `tests/conformance/fixtures/e2e/stdlib` test with `MS_CANCEL_AT_PARK=k` for every park k, on the `stats` runtime, and fails when a cancelled run ends with more live `ms-rt` blocks than the uncancelled run. On 2026-11-08 all 191 fixtures were clean at up to 16 parks each.

The counting runtime also counts Rust's own heap (`ms-rt rust heap at exit: blocks=N`; the std heap is the system allocator there), and the sweep fails on a cancelled run that ends with more Rust blocks than every one of five uncancelled runs, reproduced on two re-runs (`heap:`; worker threads leave buffers of timing-dependent size, so one uncancelled run is not a baseline), which is how `Parked`-class leaks in native code show ([guard exits](runtime-guard-exits-skip-native-rust-destructors.md)). It cannot see fd leaks; count `/proc/<pid>/fd` for those. Park counts are per process and include scheduler threads, so a threaded test can vary. The injection skips a scheduler worker's idle root park (`task::sweep::internal`), which is not an await point of the program. A cancel that ends the process (status 143) prints no counts and is not swept.

A park inside a shield (a scope close, a promise's task-end drop) is not cancelled: a real cancel stays pending under a shield, so the injection records the request and the next unshielded park reports it (`task::sweep::cancel_here`). Cancelling shielded parks had made every `close` that parks look like a leak (about 100 of the 145 first-night hits, 2026-11-15, #4052): the shielded close runs with its owner uncovered, which a real cancel never interrupts.

An implicit close is always shielded, including the close of a discarded statement result (`xs.pop()` as a statement, `drop_unused`) and of a pending temporary (`close_temp`): they were the two that were not, so a cancel arriving during such a close made it fail and then fault (`implicit-close-shielded.ms`).

A thread's promise table owns the closures of deferred promises nobody waited on; `promise::teardown` drops them (a cancelled `promise-cross-thread.ms` run leaked two blocks at every park until it did).

A close that fails at a scope end faults, and the cover for the slot (`cover_shielded_slots`) must still free the collection: the cover skipped a slot whose scope entry was discarded just before the shield, did not see a close inlined as a call on a field address, and the optional-element close left a stale payload in its place while it closed (it now puts `none` there). A cancel in a child task's park (the file write behind `append_file`) makes such a close fail, which is how the sweep found it (`failed-close-at-scope-end-frees-collection.ms`).

The unwind pass skips every call after a `move.out` that is not filled back (a hole in the owner), so a field read of a temporary (`(f()?).kind`: `move.out` then `type.release` of the rest) made it skip the rest of the function and leak what the frame held when a later park was cancelled (`random-weight-ranges.ms`); a move-out the release follows at once opens no hole.

Apply when: adding a park, a cleanup, or an `rt::Parked`; run the sweep on the touched fixture (`ms run tools/cancel-sweep.ms -- <file>`).

Found by the first sweep (baseline, not cancellation): `http-hardening.ms` "close cancels a handler parked on a request body" ends with one 16 B block even with no cancellation (a client read after the server closed the connection triggers it); the sweep compares against that baseline, and `make leak-check` owned the fix (#3083, covered by the MIR unwind pass).
