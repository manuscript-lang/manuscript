+++
title = "Source guarantees and Go representations"
weight = 94
+++

# Source guarantees and Go representations

A Go value must preserve the behavior promised by its Manuscript type. For example, generated Int arithmetic must detect overflow, and generated collections must prevent mutation through an alias. The compiler and runtime enforce guarantees that unrestricted Go values do not provide on their own.

The frontend enforces semantics that Go representations do not provide:

| Source guarantee | Go lowering |
| --- | --- |
| Checked `Int` | `int64` with checked operations and conversions |
| `Decimal` | Versioned finite decimal implementation honoring the coefficient/exponent grid, exact literals, and per-operator rounding in the numeric contract |
| Valid UTF-8 `String` | Validated construction and conversion; no raw string escape |
| Mutable records and collections | Shared record field storage and pointer-backed collection headers; explicit shallow clone |
| Immutable bytes | Encapsulated storage; copies or exclusive adapter transfer |
| Ordered maps and sets | Ordered wrappers |
| Tagged alternatives | Generated typed tags and payloads; exhaustive frontend checking |
| Recursive data | Record maps and alternative payload slices retain references; direct and mutual recursion require no extra wrapper; reject expanding generic families before Go emission |
| Value equality and hashing | Generated operations for eligible types |
| Explicit contract implementation | Frontend selection of a unique applicable concrete/generic implementation, then Go interfaces and wrappers |
| Closures and resource references | GC-retained environments, snapshot captures, and synchronized native closed-state checks |
| Lexical cleanup | Explicit `with` registrations, shielded `Closeable.close()`, and scope unwind operations |
| Task results | Native Task[T] handles retaining cached, exactly typed return values |

The frontend checks Task[T] through ordinary generics. Native handles retain runtime value storage; source cannot perform unchecked casts.

## Representation boundaries

For example, emitting a raw `int64` does not supply checked arithmetic. A raw Go slice does not establish immutable source bytes. The frontend and runtime cooperate with generated wrappers and operations to preserve those contracts.

Explicit [view constructors](../../../core-language/types/contracts.md#explicit-contract-views) create ordinary contract wrappers. There is one contract-view identity and no sharing proof in the frontend or IR. Native services synchronize their internals. Local queues rely on caller-managed Synchronized guards for concurrent access.

Contract wrappers and bound methods retain the selected implementation scope. Generic specialization carries that scope with each type argument, including nested receiver arguments; forwarding a bounded parameter must preserve its implementation evidence. Cleanup dispatch obeys the same scope rules.

Generic implementation bodies use checked substitutions; Go method selection cannot resolve overlapping source implementations. Function wrappers retain source labels/order in frontend identity even though Go erases labels. Check [recursive storage rules](../../../core-language/types/records.md#recursive-data) before emission; a generated-Go error is not a source type check.

Int division/remainder overflow handling, Float non-finite outcomes, Decimal underflow/overflow, and checked truncation conversions follow [runtime numeric outcomes](../../../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes), including parameterized runtime operands. Unchecked Go casts or a decimal package's defaults do not establish these semantics.

See [foreign conversions](../adapters/value-conversion.md), [type checking](../frontend/type-checker.md), and [scope and capture checking](../frontend/scope-checker.md).
