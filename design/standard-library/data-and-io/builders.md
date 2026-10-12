+++
title = "Local builders and immutable results"
weight = 43
+++

# Local builders and immutable results

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

A builder lets you mutate a value while constructing it locally, then freeze an immutable snapshot. Aliases refer to the same builder. Freezing may seal it so later mutation returns a runtime error.

An unsynchronized mutable builder cannot be shared concurrently. Freezing transfers no compiler-tracked ownership; the frozen collection still has to meet its ordinary element bounds.

Builders with unsynchronized mutable state are not eligible for concurrent sharing. There is no consuming function type or compiler-tracked ownership transfer. Frozen contents follow the ordinary collection element bounds.

## API

All builder names are exported by `@std/builders.ms`. They have zero-argument constructors and are opaque local references with no sharing, equality, or hashing eligibility. Type arguments can come from an explicit application or a complete expected constructor type.

| Type | Mutation | Freeze result |
| --- | --- | --- |
| `ListBuilder[T: Shareable]` | `append(value: T) -> Unit` | `List[T]` |
| `MapBuilder[K: Hashable, V: Shareable]` | `with_entry(key: K, value: V) -> Unit` | `Map[K, V]` |
| `SetBuilder[T: Hashable]` | `with_value(value: T) -> Unit` | `Set[T]` |
| `BytesBuilder` | `append(value: Int) -> Unit`, `concat(values: Bytes) -> Unit` | `Bytes` |
| `StringBuilder` | `append(value: String) -> Unit` | `String` |

`freeze()` seals the shared local object and returns its immutable snapshot. Repeated freeze returns the same value. Every mutation through any alias after sealing is a programming fault. Byte append requires 0 through 255. Map replacement preserves insertion position; set insertion ignores an already present value. Builders have no implicit cleanup or ownership transfer.

See [aggregates](../../ownership-and-cleanup/values/aggregates.md) and [collections](../../core-language/types/collections.md).
