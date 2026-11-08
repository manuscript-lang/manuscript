[Wiki](../index.md) › [Runtime](index.md)

# A pipe read needs no promise when a value is queued

Measured 2026-11-07: two producers into a middle stage into a consumer, 1M values over two pipes, took 0.33 s against 0.17 s for Go channels. Callgrind showed a promise created, waited, taken and dropped per item (about 2,000 instructions per transfer). `PipeSource.next` now asks `msrt_pipe_try` for a queued value and `msrt_pipe_ended` for the end first, and parks through `msrt_pipe_read` only when both say no: 0.14 s.

The fast path wakes writers waiting on capacity exactly as `msrt_pipe_read` does. `msrt_pipe_try` and a queued `msrt_pipe_write` pass `msrt_task_yield` every 256th operation per thread and then fault with `msrt_cancelled` if the task's cancel flag is set (a yield alone only expires the timer; the flag is acted on by the callee, and the fast path has no other check), so a consumer or producer that always finds work still meets timers, limits and cancellation (#2961; before this a timed-out consumer spun forever and the program never exited). Fixture: the timeout test in `tests/e2e/testdata/stdlib/pipe.ms`.

Apply when: changing `crates/ms-rt/src/pipe.rs` or `PipeSource`.
Verify: `bench` loop from the PR (producers, one stage, one consumer) and `tests/e2e/testdata/stdlib/pipe.ms`.
