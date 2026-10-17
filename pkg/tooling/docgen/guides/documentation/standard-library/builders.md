+++
title = "Building values"
weight = 6
+++

# Building values

Ordinary collections already support mutation. Use a builder when construction needs a sealed result. A builder returns its result when sealed. Builder aliases are ordinary references; freezing may seal the builder so later mutation reports a runtime error.

Builders are not synchronized, like ordinary collections: use one builder from one task at a time, or guard it with [Synchronized](../concurrency/synchronization.md#synchronized). There is no ownership-transfer or consuming function type.

## API

Collection builders are exported by `@std/collections.ms`; BytesBuilder by `@std/bytes.ms`; StringBuilder by `@std/string.ms`. They have zero-argument constructors and are opaque references with no equality or hashing. Type arguments can come from an explicit application or a complete expected constructor type.

| Type | Mutation | Freeze result |
| --- | --- | --- |
| `ListBuilder[T]` | `append(value: T) -> Unit` | `List[T]` |
| `MapBuilder[K: Hashable, V]` | `add(key: K, value: V) -> Unit` | `Map[K, V]` |
| `SetBuilder[T: Hashable]` | `add(value: T) -> Unit` | `Set[T]` |
| `BytesBuilder` | `append(value: Int) -> Unit`, `concat(values: Bytes) -> Unit` | `Bytes` |
| `StringBuilder` | `append(value: String) -> Unit` | `String` |

All builder mutations return `Unit`; they update the builder through its existing reference. Ordinary collection mutators return their collection for chaining; builders return their constructed value only from `freeze`. See the [migration table](../core-language/types/collections.md#naming-and-migration).

`freeze()` seals the shared local object and returns its result. Repeated freeze returns the same value. List, Map, and Set results are ordinary mutable collections; sealing prevents further builder operations, not mutation through the result. Use `.clone()` to retain a separate copy. Every builder mutation through any alias after sealing is a programming fault. Byte append requires 0 through 255. Map replacement preserves insertion position; set insertion ignores an already present value. Builders have no implicit cleanup or ownership transfer.

See [references inside other values](../core-language/types/references.md) and [collections](../core-language/types/collections.md).

<!-- manuscript-example: {"mode":"test"} -->
```manuscript
import MapBuilder from "@std/collections.ms"
import panic from "@std/faults.ms"

test "build entries with a stored Unit operation":
    let builder = MapBuilder[String, Int]()
    let add: fn(key: String, value: Int) -> Unit = builder.add
    add("a", 1)
    add("a", 2)
    let result = builder.freeze()
    if result.get("a") != some(2): return panic("builder replacement")
```
