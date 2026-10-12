+++
title = "Concurrent APIs and host lifetimes"
weight = 35
+++

# Concurrency services

[Guide index](../_index.md) · [Design index](../../_index.md)

Use `parallel` for a fixed set of operations and `Scheduler` for work managed by a longer-lived service. Parallel calls wait for their started work before returning. A scheduler waits during shutdown.

- [Parallel operations](../../concurrency/parallel.md)
- [Scheduler services](scheduler.md) — Start work under a service that tracks it and waits during shutdown.
