+++
title = "Logging and test assertions"
weight = 59
+++

# Logging and test assertions

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

## `@std/log.ms`

```text
fn write(output: WriteStream&Shareable, level: String, message: String, fields: Map[String, String], max_bytes: Int) -> Result[Unit, LibraryError]
```

## `@std/test.ms`

```text
fn assert_equal[T: Equal](actual: T, expected: T) -> Unit
fn assert_near(actual: Float, expected: Float, absolute: Float, relative: Float) -> Unit
```

Log.write emits one compact UTF-8 JSON line with level/message/fields to an explicit shared WriteStream. Allowed levels are debug/info/warn/error; fields are Map[String,String], sorted by the native JSON serializer. Max_bytes includes LF and is nonnegative. Exceeding the bound returns LimitExceeded rather than truncated output; stream failures become Failed. Write uses the stream's existing serialization/backpressure/cancellation. No implicit stderr authority, arbitrary object inspection, automatic redaction or recursive failure logging. Caller controls sensitive fields; the serializer may allocate a complete record before checking the bound, so bound inputs for untrusted messages.

Assert_equal uses the existing Equal bound and faults on inequality. Assert_near requires finite nonnegative tolerances, compares difference against max(absolute, relative * max(abs(actual),abs(expected))), rejects NaN, permits equal infinities and rejects opposite infinities. These are ordinary imported functions that supplement the existing test/assert runner. No expected-fault-catching syntax or new authority injection is added. Existing source inspect/diagram/debug metadata remain unchanged. Heap/CPU profile capabilities and richer runtime metrics remain future additions.
