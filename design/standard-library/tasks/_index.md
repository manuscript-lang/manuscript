+++
title = "Concurrent APIs and host lifetimes"
weight = 35
+++

# Concurrency services

[Guide index](../_index.md) · [Design index](../../_index.md)

Use `parallel` for a fixed set of operations, `parallel_map` for a list of inputs, and `Background` for work managed by a longer-lived service. Parallel calls wait for their started work before returning. A background service waits during shutdown.

- [Parallel operations](../../concurrency/parallel.md)
- [Bounded parallel mapping](parallel-map.md) — Run one function over a list with a limit on simultaneous calls.
- [Background services](background.md) — Start work under a service that tracks it and waits during shutdown.
