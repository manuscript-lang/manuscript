+++
title = "Builders and sealed results"
weight = 43
+++

# Builders and sealed results

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A builder supports mutable construction and returns its result when sealed. Builder aliases are ordinary references; freezing may seal the builder so later mutation reports a runtime error.

Builders synchronize mutation and freeze across all aliases. Freezing seals the object atomically; an append racing with freeze either contributes to the snapshot or faults after sealing. Concurrent appends have nondeterministic order. There is no ownership-transfer or consuming function type.

## API

All builder names are exported by `@std/builders.ms`. They have zero-argument constructors and are opaque references with no equality or hashing. Type arguments can come from an explicit application or a complete expected constructor type.

| Type | Mutation | Freeze result |
| --- | --- | --- |
| `ListBuilder[T]` | `append(value: T) -> Unit` | `List[T]` |
| `MapBuilder[K: Hashable, V]` | `with_entry(key: K, value: V) -> Unit` | `Map[K, V]` |
| `SetBuilder[T: Hashable]` | `with_value(value: T) -> Unit` | `Set[T]` |
| `BytesBuilder` | `append(value: Int) -> Unit`, `concat(values: Bytes) -> Unit` | `Bytes` |
| `StringBuilder` | `append(value: String) -> Unit` | `String` |

`freeze()` seals the shared local object and returns its result. Repeated freeze returns the same value. List, Map, and Set results are ordinary mutable collections; sealing prevents further builder operations, not mutation through the result. Use `.clone()` to retain a separate copy. Every builder mutation through any alias after sealing is a programming fault. Byte append requires 0 through 255. Map replacement preserves insertion position; set insertion ignores an already present value. Builders have no implicit cleanup or ownership transfer.

See [aggregates](../../ownership-and-cleanup/values/aggregates.md) and [collections](../../core-language/types/collections.md).
