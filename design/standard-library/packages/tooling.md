+++
title = "Logging"
weight = 59
+++

# Logging

[Standard library guide](../_index.md) · [Coverage](coverage.md) · [Common contracts](contracts.md)

Write structured logs to an explicit output stream. Logging returns expected errors. Tests use ordinary conditional returns to check their results.

## `@std/log.ms`

```text
fn write(output: WriteStream&Shareable, level: String, message: String, fields: Map[String, String], max_bytes: Int) -> Result[Unit, LogError]
```

`write` emits one compact UTF-8 JSON line to the supplied shared WriteStream. It contains `level`, `message`, and `fields`. Allowed levels are `debug`, `info`, `warn`, and `error`. Fields are a `Map[String, String]`, sorted by the native JSON serializer.

`max_bytes` must be nonnegative and includes the final LF. Excess output returns `LimitExceeded`; it is not truncated. Stream failures become `Failed`. Writes use the stream's existing synchronization, backpressure, and cancellation behavior.

The caller chooses the output and sensitive fields. The function provides no implicit stderr access, arbitrary object inspection, automatic redaction, or recursive failure logging. Serialization may allocate a complete record before checking the byte limit, so bound untrusted inputs too.

## Tests

Tests use ordinary `if`/`return` guards; see [semantic conformance tests](../../compiler/conformance/semantic-tests.md). No expected-fault-catching syntax or authority injection is added. Heap/CPU profiling and richer runtime metrics remain future work. Existing inspect, diagram, and debug metadata contracts are unchanged.
