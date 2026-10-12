+++
title = "Core and standard types"
weight = 33
+++

# Core and standard types

[Guide index](../_index.md) · [Chapter index](_index.md) · [Design index](../../_index.md)

Use this table to find a type's meaning and import path. “Implicit intrinsic” means the type is available without an import. Import other type names from the listed module when you use them in source.

| Type | Meaning | Import from |
| --- | --- | --- |
| `Bool` | `true` or `false` | Implicit intrinsic |
| `Int` | Signed 64-bit integer; checked arithmetic | Implicit intrinsic |
| `Float` | IEEE 754 binary64 | Implicit intrinsic |
| `Decimal` | Base-10, 34 significant digits; round half to even | `@std/decimal.ms` |
| `String` | Immutable, valid UTF-8 text | Implicit intrinsic |
| `Bytes` | Immutable byte sequence | `@std/bytes.ms` |
| `Unit` | One value, `unit` | Implicit intrinsic |
| `Never` | No possible value | Implicit intrinsic |
| `List[T]`, `Map[K, V]`, `Set[T]` | Immutable homogeneous collections with arbitrary value elements; keys require Hashable | `@std/collections.ms` |
| `MapEntry[K, V]` | Immutable standard record with `key: K` and `value: V`; map iteration yields entries | `@std/collections.ms` |
| `Optional[T]` | `some(value: value)` or `none` | `@std/optional.ms` |
| `Result[T, E]` | `ok(value: value)` or `error(cause: cause)` | `@std/result.ms` |
| `ExecutionError` | Joined-group timeout or crash | `@std/tasks.ms` |
| `Background` | Synchronized service managing work under a fixed lifetime | `@std/tasks.ms` |
| `WorkStatus`, `StartError`, `BackgroundFailure` | Background status, admission failure, and failure reports | `@std/tasks.ms` |
| `OperationId` | Identity of a runtime operation, used for diagnostics and Background status/cancellation | `@std/tasks.ms` |
| `Synchronized[T]`, `SynchronizedGuard[T]` | Shared value protected by a scoped mutex guard | `@std/sync.ms` |
| `Closeable` | Standard `close() -> Unit` cleanup contract | `@std/cleanup.ms` |
| `File`, `ReadStream`, `WriteStream` | Resource contracts; all implementations synchronize lifecycle access | `@std/io.ms` |
| `Duration`, `Instant` | Checked nanosecond duration and monotonic clock instant | `@std/time.ms` |
| `Process` | CLI authority roots | `@std/cli.ms` |
| `Files`, `IoError` | File capability contract and expected I/O failures | `@std/io.ms` |
| `Clock` | Monotonic clock capability contract | `@std/time.ms` |

Functions and closures are ordinary values; runtime tasks are not exposed as source ownership types. Fixed parallel result packs preserve positional types and use bracket destructuring; they are not homogeneous lists.

References do not extend an object's open lifetime. Use `with` for deterministic release and `Result` for expected operation failures. See [parallel](../../concurrency/parallel.md), [background services](../tasks/background.md), and [Closeable](../../ownership-and-cleanup/cleanup/closeable.md).

The [standard API contract](prelude.md) defines visibility, signatures, optional arguments, and pack typing.

## General-purpose types

The [package guide](../packages/_index.md) adds opaque `BigInt` (`@std/bigint.ms`), `Regex` (`@std/regex.ms`) and wall-clock `Timestamp` (`@std/time.ms`); `JsonValue`/`JsonLimits` (`@std/json.ms`); structured format/filesystem/archive records; and package-specific error types (see [error contracts](../packages/contracts.md#errors)). New capability contracts are `FileSystem`, `Entropy`, `WallClock` and `System`, supplied by explicit CLI Process fields. TCP/TLS `Connection`, `Listener` and `DatagramSocket` are acquired through the existing Network authority. All names remain individually imported; no additions enter the intrinsic prelude. See [coverage](../packages/coverage.md) for implemented equivalents and remaining gaps.
