+++
title = "Standard library"
weight = 31
+++

# Standard library guide

[Design index](../_index.md)

Use this chapter to find standard types and operations. Most names need an explicit import from an `@std/...ms` module. Start with the type catalog, or choose a task from the sections below. The package pages list exact signatures and explain their limits.

## API reference

[Browse all implemented modules](reference/_index.md), including the intrinsic prelude. The reference is generated from compiler definitions; [special call rules](call-rules.md) cover APIs with contextual signatures.

## Reading order

### 1. [Standard types](types/_index.md)

- [Core and standard types](types/catalog.md) — Find a type, its meaning, and its import path.
- [Standard imports and API typing](types/prelude.md) — Check exact import identities, callable types, and standard API rules.

### 2. [Concurrent APIs and host lifetimes](tasks/_index.md)

- [Bounded parallel mapping](tasks/parallel-map.md) — Run one function over a list with a limit on simultaneous calls.
- [Background services](tasks/background.md) — Start work under a service that tracks it and waits during shutdown.

### 3. [Data, state, and I/O](data-and-io/_index.md)

- [Minimum data operations](data-and-io/operations.md) — Look up the basic methods on collections, text, bytes, and numeric values.
- [Readers, writers, and streams](data-and-io/streams.md) — Read and write bytes, recognize end-of-input, and close streams.
- [Bounded queues](data-and-io/queues.md) — Connect producers and consumers with bounded storage.
- [Synchronized state, pools, and leases](data-and-io/synchronized-state.md) — Coordinate shared state and acquire a pool lease with scoped cleanup.
- [Local builders and immutable snapshots](data-and-io/builders.md) — Construct a value with local mutation, then freeze an immutable snapshot.

### 4. [Application hosts](hosts/_index.md)

- [HTTP request hosts](hosts/http.md) — Use HTTP clients or request hosts with bounded bodies and cleanup.
- [CLI application hosts](hosts/cli.md)

### 5. [General-purpose packages](packages/_index.md)

- [Node.js and Go coverage](packages/coverage.md) — See what is implemented and what remains outside the library.
- [Common package contracts](packages/contracts.md) — Review the errors, limits, and authority rules shared by packages.
- [Expanded library conformance](packages/conformance.md) — Find executable checks for package behavior and limits.

## Runtime facilities

These are ordinary library facilities with effect, sharing, lifetime, and cancellation contracts. They add no concurrency syntax. Host-created requests, sessions, applications, and CLI runs establish fixed execution contexts. Parallel APIs join before returning; background services implement `Closeable` and join during shutdown.

Standard imports, immutable data, CLI streams, and concurrent APIs have concrete signatures. Queue, pool, builder, HTTP server, and buffered subprocess APIs have concrete contracts. The general-purpose package guide adds executable data, codec, filesystem, cryptographic, networking and HTTP client operations. See [outstanding decisions](../compiler/conformance/scope.md#outstanding-decisions).
