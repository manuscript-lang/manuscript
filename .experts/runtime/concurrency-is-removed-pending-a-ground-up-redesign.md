[Wiki](../index.md) › [Runtime](index.md)

# Concurrency is removed pending a ground-up redesign

Decision: the user removed the concurrency features (TaskGroup, Task, Scheduler, Synchronized, BlockingQueue, `check_cancelled`, `yield_now`, and their lowering, runtime, tooling, tests, examples, and documentation) because concurrency should be rebuilt correctly from the ground up. Do not restore the old APIs or add channels, locks, or tasks without a new user direction. Host-level cancellation (SIGINT/SIGTERM) and `with` cleanup remain. Queue stays a single-threaded FIFO. Older entries or docs that mention Scheduler or timed work predate this removal.

Apply when: a task proposes concurrent work, locks, task handles, or revives the removed APIs.
Evidence: the user's removal request in the "Manuscript agent feedback and experience" project thread; [runtime conventions](../../documentation/contributing/runtime-conventions.md).
Verify: no `@std/tasks.ms` or `@std/sync.ms`; `BlockingQueue` is absent from `queue.ms`.
