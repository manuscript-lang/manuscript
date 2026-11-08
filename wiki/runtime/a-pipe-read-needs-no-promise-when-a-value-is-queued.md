[Wiki](../index.md) › [Runtime](index.md)

# A pipe read needs no promise when a value is queued

Measured 2026-11-07: two producers into a middle stage into a consumer, 1M values over two pipes, took 0.33 s against 0.17 s for Go channels. Callgrind showed a promise created, waited, taken and dropped per item (about 2,000 instructions per transfer). `PipeSource.next` now asks `msrt_pipe_try` for a queued value and `msrt_pipe_ended` for the end first, and parks through `msrt_pipe_read` only when both say no: 0.14 s.

The fast path wakes writers waiting on capacity exactly as `msrt_pipe_read` does. A reader that never waits cannot see a cancel or timeout until the queue drains (a pipe fed by another thread faster than it is read); the old path behaved the same for an infinite producer (`MS_THREADS=4`, both exit by timeout), so this is not a regression.

Apply when: changing `crates/ms-rt/src/pipe.rs` or `PipeSource`.
Verify: `bench` loop from the PR (producers, one stage, one consumer) and `tests/e2e/testdata/stdlib/pipe.ms`.
