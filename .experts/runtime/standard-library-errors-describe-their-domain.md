[Wiki](../index.md) › [Runtime](index.md)

# Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. The newer simplification lets implementing errors pass directly into Error boundaries and propagate with `try`; the concrete receiver and fields are retained for specific handling.

Decision: keep typed diagnostic information in ordinary domain error fields. The request to simplify error handling supersedes the extra details wrapper introduced earlier. Records and alternative case payloads already support fields of different types; `Result[T, E]` and `try` retain them. Add a cause field only when the domain needs it. Ordinary errors reuse their original runtime value at an Error boundary; local implementations and generic receivers retain scoped dispatch evidence.

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../../stdlib/intrinsics.ms); [compiled typed errors](../../tests/e2e/testdata/accept/library-errors.ms); [cross-module error dispatch](../../tests/e2e/testdata/projects/error_boundaries/conformance_test.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.

---
Topics: [Errors and results](../topics/errors-and-results.md)
