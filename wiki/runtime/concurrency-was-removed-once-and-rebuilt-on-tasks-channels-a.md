[Wiki](../index.md) › [Runtime](index.md)

# Concurrency was removed once and rebuilt on tasks, channels, and workers

Decision: the first concurrency features (Scheduler, Synchronized, BlockingQueue, `check_cancelled`, `yield_now`) were removed so concurrency could be rebuilt correctly. The rebuild lives in `@std/concurrency/tasks.ms` (`Task`, `TaskGroup`, `cancelled()`), `@std/io/channels.ms`, `@std/concurrency/sync.ms`, and `@std/concurrency/workers.ms`. Do not restore the removed names. Older entries or docs that mention Scheduler or timed work predate the rebuild.


Apply when: a task proposes concurrent work, locks, task handles, or revives the removed APIs.
Evidence: [tasks](../../stdlib/tasks.ms), [workers](../../stdlib/workers.ms), [taskgroup proposal](../../proposals/taskgroup.md), [worker-threads proposal](../../proposals/worker-threads.md), [runtime conventions](../../documentation/contributing/runtime-conventions.md).
Verify: `BlockingQueue` is absent from `queue.ms`; new concurrency work follows the proposals above.
