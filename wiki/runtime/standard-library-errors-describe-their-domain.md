[Wiki](../index.md) › [Runtime](index.md)

# Standard-library errors describe their domain

Decision: return more specific standard-library errors instead of the shared `LibraryError`. Public error types live with their package and contain domain-relevant cases. All standard errors explicitly implement the ordinary `Error` operation contract. The newer simplification lets implementing errors pass directly into Error boundaries and propagate with `try`; the concrete receiver and fields are retained for specific handling.

Apply when: adding or changing fallible standard APIs, native adapters, or error propagation.
Evidence: [error contracts](../../stdlib/intrinsics.ms); [compiled typed errors](../../tests/e2e/testdata/accept/library-errors.ms); [cross-module error dispatch](../../tests/e2e/testdata/projects/error_boundaries/conformance_test.ms).
Verify: native error values carry the declared Result's error identity; unrelated domains cannot propagate implicitly; stream helpers preserve the original IoError case and payload.
