[Wiki](../index.md) › [Language](index.md)

# Result's error type is bounded by Error

Decision: Chinmay required `Result[T, E: Error]`; arbitrary error values (`String`, `Int`, collections) are rejected. Plain text uses `TextError("message")` and domain errors declare `impl Error`. Generic helpers over Result write `E: Error`.

Verified: the bound lives on `Result` in `stdlib/core.ms`, so annotations and inferred call results (including `Optional.ok_or`) hit the ordinary type-argument bound check. Native declaration default bounds (`ok_or[E: Error = MissingValue]`) are checked after standard impls bind.

Apply when: adding Result-returning APIs, examples, or tests that need an error value.
Evidence: [Result source](../../stdlib/core.ms), [results guide](../../documentation/core-language/errors/results.md).
Verify: `Result[Int, String]` fails with "String does not satisfy Error"; `Result[Int, TextError]` and `Result[T, Error]` pass.

---
Topics: [Errors and results](../topics/errors-and-results.md)
