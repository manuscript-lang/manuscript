+++
title = "Concurrent APIs and host lifetimes"
weight = 35
+++

# Concurrency services

[Guide index](../_index.md) · [Design index](../../_index.md)

Use TaskGroup for scoped work with typed results and Scheduler for immediate or timed work managed by a longer-lived service. A group joins explicitly or cancels and joins during scope cleanup. A scheduler waits during shutdown.

- [Task groups](../../concurrency/task-groups.md)
- [Scheduler services](scheduler.md) — Start work under a service that tracks it and waits during shutdown.
