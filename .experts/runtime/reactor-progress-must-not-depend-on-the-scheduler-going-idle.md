[Wiki](../index.md) › [Runtime](index.md)

# Reactor progress must not depend on the scheduler going idle

Verified: tasks that keep each other ready through channels or yields can prevent `reactor_wait`
from running indefinitely. Checking only task kill deadlines at switches still starves sleep and
park timers, readable descriptors, remote completion posts, and pending isolate cancellation.
Service those events at switches too, without blocking; skip clock and poll calls when there
are no corresponding waits.

Apply when: changing task wake paths, reactor servicing, or deadline checks.
Evidence: [scheduler regressions](../../crates/ms-rt/src/task.rs) (`timers_progress_while_tasks_stay_ready`,
`io_progresses_while_tasks_stay_ready`, `remote_posts_progress_while_tasks_stay_ready`).
Verify: ready events finish before a bounded busy task finishes yielding; retain shielded cleanup tests.

---
Topics: [Concurrency and cancellation](../topics/concurrency-and-cancellation.md)
