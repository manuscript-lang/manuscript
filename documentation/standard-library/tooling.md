+++
title = "Logging"
weight = 18
+++

# Logging

API reference: [log](reference/log.md).

Write structured logs to an explicit output stream. Logging returns expected errors. Tests use ordinary conditional returns to check their results.

`write` emits one compact UTF-8 JSON line to the supplied shared WriteStream. It contains `level`, `message`, and `fields`. Allowed levels are `debug`, `info`, `warn`, and `error`. Fields are a `Map[String, String]`, sorted by the native JSON serializer.

`max_bytes` must be nonnegative and includes the final LF. Excess output returns `LimitExceeded`; it is not truncated. Stream failures become `Failed`. Writes use the stream's existing synchronization, backpressure, and cancellation behavior.

The caller chooses the output and sensitive fields. The function provides no implicit stderr access, arbitrary object inspection, automatic redaction, or recursive failure logging. Serialization may allocate a complete record before checking the byte limit, so bound untrusted inputs too.

## Tests

Use `test "name":` blocks and ordinary `if` guards. Return `panic(message: ...)` from `@std/faults.ms` when a check fails; a bare `return` completes the test successfully. Run test blocks with `ms test file.ms`. The [developer tools](../developer-tooling/implementation.md) cover inspection, debugging, and CPU and heap profiling.
