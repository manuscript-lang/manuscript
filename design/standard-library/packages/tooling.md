+++
title = "Logging and test assertions"
weight = 59
+++

# Logging and test assertions

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Write structured logs to an explicit output stream and use imported assertions in tests. Logging returns expected errors; a failed assertion produces a programming fault.

## `@std/log.ms`

```text
fn write(output: WriteStream&Shareable, level: String, message: String, fields: Map[String, String], max_bytes: Int) -> Result[Unit, LibraryError]
```

## `@std/test.ms`

```text
fn assert_equal[T: Equal](actual: T, expected: T) -> Unit
fn assert_near(actual: Float, expected: Float, absolute: Float, relative: Float) -> Unit
```

## Logging

`write` emits one compact UTF-8 JSON line to the supplied shared WriteStream. It contains `level`, `message`, and `fields`. Allowed levels are `debug`, `info`, `warn`, and `error`. Fields are a `Map[String, String]`, sorted by the native JSON serializer.

`max_bytes` must be nonnegative and includes the final LF. Excess output returns `LimitExceeded`; it is not truncated. Stream failures become `Failed`. Writes use the stream's existing synchronization, backpressure, and cancellation behavior.

The caller chooses the output and sensitive fields. The function provides no implicit stderr access, arbitrary object inspection, automatic redaction, or recursive failure logging. Serialization may allocate a complete record before checking the byte limit, so bound untrusted inputs too.

## Assertions

`assert_equal` uses the existing `Equal` bound and faults when the values differ.

`assert_near` requires finite, nonnegative tolerances. It compares the difference against:

```text
max(absolute, relative * max(abs(actual), abs(expected)))
```

NaN fails. Equal infinities pass; opposite infinities fail.

These are ordinary imported functions for the existing test runner. They add no expected-fault-catching syntax or authority injection. Heap/CPU profiling and richer runtime metrics remain future work. Existing inspect, diagram, and debug metadata contracts are unchanged.
