+++
title = "Source guarantees and Go representations"
weight = 94
+++

# Source guarantees and Go representations

A Go value must preserve the behavior promised by its Manuscript type. For example, generated Int arithmetic must detect overflow, and generated collections must preserve shared mutation through aliases. The compiler and runtime enforce guarantees that unrestricted Go values do not provide on their own.

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

The current shared runtime ABI boxes locals, captures, arguments, and return
values as Go `any`. Within statically checked `Int` and `Float` expressions,
lowering emits typed literals and scalar operations; integer arithmetic retains
overflow and zero-divisor checks, and floating arithmetic rounds at each source
operation. Equality still uses the selected implementation scope.

Direct calls to the checked native `List.at` and `Optional.unwrap` operations
share runtime helpers with bound-method dispatch, avoiding temporary callable
wrappers. Indexing still returns an Optional, including `none` for out-of-range
indexes; it does not introduce unchecked access. Bound methods and generic
callable dispatch retain the ordinary ABI. The reproducible native workloads in
`scripts/benchmarks/` measure numeric loops, calls, list reads, and Game of Life;
they do not establish that values or source functions are fully unboxed.

For example, emitting a raw `int64` does not supply checked arithmetic. A raw Go slice does not establish immutable source bytes. The frontend and runtime cooperate with generated wrappers and operations to preserve those contracts.

Explicit [view constructors](../../../core-language/types/contracts.md#explicit-contract-views) create ordinary contract wrappers. There is one contract-view identity and no sharing proof in the frontend or IR. Native services synchronize their internals. Local queues rely on caller-managed Synchronized guards for concurrent access.

Contract wrappers and bound methods retain the selected implementation scope. Generic specialization carries that scope with each type argument, including nested receiver arguments; forwarding a bounded parameter must preserve its implementation evidence. Cleanup dispatch obeys the same scope rules.

Generic implementation bodies use checked substitutions; Go method selection cannot resolve overlapping source implementations. Function wrappers retain source labels/order in frontend identity even though Go erases labels. Check [recursive storage rules](../../../core-language/types/records.md#recursive-data) before emission; a generated-Go error is not a source type check.

Int division/remainder overflow handling, Float non-finite outcomes, Decimal underflow/overflow, and checked truncation conversions follow [runtime numeric outcomes](../../../core-language/basics/numbers-and-booleans.md#runtime-numeric-outcomes), including parameterized runtime operands. Unchecked Go casts or a decimal package's defaults do not establish these semantics.

See [foreign conversions](../adapters/value-conversion.md), [type checking](../frontend/type-checker.md), and [scope and capture checking](../frontend/scope-checker.md).

## Large List literals

Optimized lowering treats List literals with more than 1,024 elements separately
from small expressions. Complete checked Int, Float, Bool and String literals
use private typed constant data and the runtime's fresh-copy constructors. Int
remains signed 64-bit and Float remains binary64. Unary numeric literals use
those same checked widths; private initialization retains negative Float zero,
including underflow rounded to zero. Data tables never become source List
backing, and records, nested collections, Decimal and effectful expressions
never become shared global elements.

Other large literals allocate one fresh sized List header and backing, then fill
it through initialization helpers of at most 64 elements. Each element finishes
before the next begins. The runtime initialization setters add no cancellation
checkpoints; source expressions retain their existing checkpoints, fault sites,
cleanup and enclosing return/try/loop exits. The completed List is published only
after `FinishListInitialization`. Typed and generic paths use the runtime's
authoritative storage rather than accessing storage fields from lowering.
Deferred primitive IR operands consume the canonical scalar lowering context.
Known calls use the same native entry, argument conversions and source guard as
other typed scalar operations; literal initialization retains that boundary.

Explicit Debug keeps its existing literal policy. Compiler callers selecting a
native build kind before lowering should use `CompileSourceForBuild` or
`CompileFileForBuild`; builders continue to honor the supplied `Result.Source`,
including caller edits. The Result layout and source collection APIs do not
change. Generated Go and build pins change, so update strict project pins with
`ms lock ms.toml` after upgrading. String/List/Bytes `slice` retains its strict
Result contract; source callers still handle or unwrap that result.
