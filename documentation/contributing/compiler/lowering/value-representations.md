+++
title = "Source guarantees and Go representations"
weight = 94
+++

# Source guarantees and Go representations

A Go value must keep the behavior its Manuscript type promises: `Int` arithmetic detects overflow and collections prevent mutation through aliases. The compiler and runtime enforce what raw Go values do not.

| Source guarantee | Go lowering |
| --- | --- |
| Checked `Int` | `int` (platform-sized) with checked operations and conversions |
| `Decimal` | Versioned finite decimal implementation honoring the coefficient/exponent grid, exact literals, and per-operator rounding in the numeric contract |
| Valid UTF-8 `String` | Validated construction and conversion; no raw string escape |
| Mutable records and collections | `*Name` structs and `*rt.List/Map/Set`; explicit shallow clone |
| Immutable bytes | Encapsulated storage; copies or exclusive adapter transfer |
| Ordered maps and sets | `rt.Map`/`rt.Set`, insertion ordered, matching keys with an `rt.Keys` |
| Tagged alternatives | Sealed interface with one `Name_Case` struct per case; exhaustive frontend checking |
| Recursive data | Records are pointers, so direct and mutual recursion need no wrapper; reject expanding generic families before Go emission |
| Value equality and hashing | `==` where Go equality is Manuscript equality; otherwise generated `equal_T`/`key_T` helpers |
| Explicit contract implementation | Frontend selection of a unique applicable concrete/generic implementation, then Go interfaces and wrappers |
| Closures and resource references | GC-retained environments, snapshot captures, and native closed-state checks |
| Lexical cleanup | Explicit `with` registrations, shielded `Closeable.close()`, and scope unwind operations |

The frontend checks `Task[T]` through ordinary generics; source cannot perform unchecked casts.

## Representation boundaries

- Locals, captures, arguments, and results have their Go types ([Go representation](../../go-lowering-representation.md)); nothing is boxed.
- `Int` and `Float` operations are typed Go operations with overflow and zero-divisor checks, rounding floats at each source operation. A raw `int` or Go slice gives neither checked arithmetic nor immutable bytes, so the lowerer calls the checked `rt` operation. `bench/language/` measures numeric loops, calls, list reads, and Game of Life.
- Members on a statically typed receiver are direct `rt` calls like `List_At` or `Map_Get`, instantiated at its type arguments. Indexing still returns an Optional.
- Explicit [view constructors](../../../core-language/types/contracts.md#explicit-contract-views) create ordinary contract wrappers: one view identity, no sharing proof.
- Wrappers and bound methods keep their implementation scope. Generic specialization carries it with each type argument, including nested receivers; forwarding a bounded parameter keeps its evidence. Cleanup dispatch follows the same rules.
- Generic implementation bodies use checked substitutions, because Go method selection cannot resolve overlapping implementations. Function wrappers keep labels and order in frontend identity even though Go erases them.
- Check [recursive storage rules](../../../core-language/types/records.md#recursive-data) before emission; a Go error is not a source check.
- Int division and remainder overflow, Float non-finite results, Decimal underflow and overflow, and checked truncation follow [runtime numeric outcomes](../../../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes). Unchecked Go casts or a decimal package's defaults do not establish them.

See [type checking](../frontend/type-checker.md) and [scope and capture checking](../frontend/scope-checker.md).
