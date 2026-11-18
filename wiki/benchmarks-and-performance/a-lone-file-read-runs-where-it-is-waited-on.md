[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A lone file read runs where it is waited on

Verified (2026-11-18): a serial `read_file(path).wait()` spent about 60% of its instructions starting a task, parking and switching (callgrind, 2,000 small files). `promise_when_idle` defers the read to its first waiter when the creator is the only live task (`msrt_promise_start_idle`), and starts a `Here` task as usual when others run, so overlapping reads still overlap. 8,290 to 4,140 instructions per read. `read_file` also opens with `O_NONBLOCK` and one `fstat` instead of `stat`, `open`, `fstat`.

Apply when: an operation completes without blocking for long and is usually waited on at once. Do not use it for fetches or connects, which must overlap even when the program has one task.
