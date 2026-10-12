+++
title = "Data, state, and I/O"
weight = 38
+++

# Data, state, and I/O

[Guide index](../_index.md) · [Design index](../../_index.md)

Choose a facility based on what you need to do: work with data values, read or write streams, pass values through a queue, coordinate shared state, or build a value locally. I/O resources need explicit cleanup.

- [Minimum data operations](operations.md) — Look up the basic methods on collections, text, bytes, and numeric values.

- [Readers, writers, and streams](streams.md) — Read and write bytes, recognize end-of-input, and close streams.
- [Local queues](queues.md) — Use a bounded FIFO locally, or share it through Synchronized.
- [Synchronized values, pools, and leases](synchronized-state.md) — Coordinate shared state and acquire a pool lease with scoped cleanup.
- [Builders and sealed results](builders.md) — Construct a value with synchronized mutation, then seal the builder and obtain its result.
