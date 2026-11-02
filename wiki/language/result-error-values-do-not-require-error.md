[Wiki](../index.md) › [Language](index.md)

# Result error values do not require Error

Decision (2026-10-31): `Result[T, E]` accepts any value `E`, with no reporting bound ("we dont need mandaory interface"). Since 2026-11-01 `Error` is a record ([errors are plain values](errors-are-plain-values-with-a-fixed-shape.md)), so there is no interface to implement and no widening into it.

Apply when: adding Result-returning APIs, adapters, examples, or tests.
Evidence: [Result source](../../stdlib/core.ms), [results guide](../../documentation/core-language/errors/results.md), [regression cases](../../tests/e2e/testdata/accept/result-error-values.ms).
Verify: records, alternatives and `Int!String` pass; context-free `error("message")` still needs a success type; `try` rejects a different error type.
