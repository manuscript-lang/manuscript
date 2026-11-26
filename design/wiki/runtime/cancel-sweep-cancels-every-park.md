[Wiki](../index.md) › [Runtime](index.md)

# The cancel sweep cancels each test at every park

Verified: `make cancel-sweep` (`tools/cancel-sweep.ms`) reruns each `tests/lang/stdlib` test with `MS_CANCEL_AT_PARK=k` for every park k, on the `stats` runtime (`cmake --preset stats`, see [the counting runtime](../testing-and-conformance/the-counting-runtime-is-the-stats-preset.md)), and fails when a cancelled run ends with more live runtime blocks than the uncancelled run. Cancels leave by return ([faults and cancels leave by return](faults-and-cancels-leave-by-return.md)); the Rust unwind pass and its cleanup stack that earlier sweep fixes targeted are gone.

- It cannot see fd leaks; count `/proc/<pid>/fd` for those. Park counts are per process and include scheduler threads, so a threaded test can vary. A cancel that ends the process (status 143) prints no counts and is not swept; a run that ends in `terminated by signal` is a leak hit (a SIGSEGV once showed only as a stray leak elsewhere). Reproduce a park by hand with `MS_CANCEL_AT_PARK=k ms test file --test name`.
- A park inside a shield (a scope close, a promise's task-end drop) is not cancelled: a real cancel stays pending under a shield, so the injection records the request and the next unshielded park reports it. Cancelling shielded parks made every `close` that parks look like a leak (about 100 of the 145 first-night hits, 2026-11-15, #4052).
- A task started while its spawner is shielded is shielded work too: a close that writes through a child task (`append_file(..).wait()` in a `close`) otherwise had the child cancelled during a shielded close, and about 90 of the 119 leaks of 2026-11-18 were that artifact; no real cancel reaches such a child.
- An implicit close is always shielded, including the close of a discarded statement result (`xs.pop()` as a statement) and of a pending temporary: a cancel arriving during such a close made it fail and then fault (`implicit-close-shielded.ms`).
- A native that raises a cancel jumps, so it must free everything its frame owns first, parameters included (the Rust `msstd_process_command_run` leaked its argument vectors whenever `run` was cancelled, `host.ms`).
- A promise that holds a value with closeable parts (a promise returned by a promise) must be closed with its type, which only compiled code can do: the runtime's descriptor drop of a `Promise` frees nothing, so the inner promise kept its two closures when the outer one was dropped by the runtime (`promise-cross-thread.ms`, only with several threads). `msrt_promise_close` cancels and joins the work and frees the slot in one call.
- A baseline is not a regression: `http-hardening.ms` "close cancels a handler parked on a request body" ends with one 16 B block even with no cancellation (a client read after the server closed the connection triggers it); the sweep compares against the uncancelled run, and `make leak-check` owns that fix (#3083).
- A negative live count is a double free: find the block by recording every allocation and free address (`MS_STATS_TRACE=1`).

Apply when: adding a park, a cleanup, or a native that waits; run the sweep on the touched fixture (`ms run tools/cancel-sweep.ms -- <file>`).
Evidence: `tools/cancel-sweep.ms`, `src/runtime/core/stats.c`, [counting runtime](../testing-and-conformance/the-counting-runtime-is-the-stats-preset.md).
Verify: `make cancel-sweep` reports no leak for the fixtures you touched.
