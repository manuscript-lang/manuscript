+++
title = "Concurrent APIs and host lifetimes"
weight = 35
+++

# Concurrency services

[Guide index](../_index.md) · [Design index](../../_index.md)

Choose joined operations for request work and explicit background services for work that outlives the caller. Every concurrency API and supporting type is an individual standard export; none enters the intrinsic prelude. See [concurrency imports](../../concurrency/_index.md#importing-concurrency-apis).

- [Parallel operations](../../concurrency/parallel.md)
- [Bounded parallel mapping](parallel-map.md)
- [Background services](background.md)
