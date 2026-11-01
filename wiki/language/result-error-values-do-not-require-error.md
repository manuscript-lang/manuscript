[Wiki](../index.md) › [Language](index.md)

# Result error values do not require Error

Decision (2026-10-31): the owner approved removing mandatory Error conformance: "lets do 1st one, we dont need mandaory interface". `Result[T, E]` accepts ordinary values, including named records/cases and primitive payloads; value-only helpers use unconstrained `E`.

`Error.message()` remains an opt-in reporting contract. Bare `T!` still selects `Result[T, Error]`, so widening to it requires an implementation; exact-`E` propagation does not. Keep `E: Error` where a helper reports or widens the error. Structured reports were not approved.

Apply when: adding Result-returning APIs, adapters, reporting boundaries, examples, or tests.
Evidence: [Result source](../../stdlib/core.ms), [results guide](../../documentation/core-language/errors/results.md), [regression cases](../../tests/e2e/testdata/accept/result-error-values.ms).
Verify: reportless records/cases and `Int!String` pass; context-free `error("message")` still needs a success type; unrelated errors and reportless-to-Error conversion remain rejected.
