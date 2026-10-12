+++
title = "Standard library"
weight = 31
+++

# Standard library guide

[Design index](../_index.md)

Choose standard types and runtime facilities by the lifetime, cancellation, and authority contracts they provide.

## API reference

[Browse all implemented modules](reference/_index.md), including the intrinsic prelude. The reference is generated from compiler definitions; [special call rules](call-rules.md) cover APIs with contextual signatures.

## Reading order

### 1. [Standard types](types/_index.md)

- [Core and standard types](types/catalog.md)
- [Standard imports and API typing](types/prelude.md)

### 2. [Concurrent APIs and host lifetimes](tasks/_index.md)

- [Bounded parallel mapping](tasks/parallel-map.md)
- [Background services](tasks/background.md)

### 3. [Data, state, and I/O](data-and-io/_index.md)

- [Minimum data operations](data-and-io/operations.md)
- [Readers, writers, and streams](data-and-io/streams.md)
- [Bounded queues](data-and-io/queues.md)
- [Synchronized state, pools, and leases](data-and-io/synchronized-state.md)
- [Local builders and immutable snapshots](data-and-io/builders.md)

### 4. [Application hosts](hosts/_index.md)

- [HTTP request hosts](hosts/http.md)
- [CLI application hosts](hosts/cli.md)

## Runtime facilities

These are ordinary library facilities with effect, sharing, lifetime, and cancellation contracts. They add no concurrency syntax. Host-created requests, sessions, applications, and CLI runs establish fixed execution contexts. Parallel APIs join before returning; background services implement `Closeable` and join during shutdown.

Standard imports, immutable data, CLI streams, and concurrent APIs have concrete signatures. Queue, pool, builder, HTTP, and subprocess APIs still need details. See [outstanding decisions](../compiler/conformance/scope.md#outstanding-decisions).
