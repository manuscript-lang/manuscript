[Wiki](../index.md) › [Language](index.md)

# Recover concrete contract receivers through checked matching

Decision: a common Error contract must allow generic diagnostics and specific handling without discarding the concrete error. The user requested constructing errors once and passing them directly into the root Error interface. An explicit implementation establishes the relationship; assignments, arguments, returns, Result error widening, and `try` can use it without a written view conversion. Ordinary domain fields contain typed details. Unrelated domains and other interfaces retain exact compatibility.

Apply when: changing Error boundaries, contract views, matching, or native standard implementations.
Evidence: [contract type patterns](../../documentation/core-language/control-flow/pattern-matching.md#contract-type-patterns); [common error boundary](../../documentation/core-language/errors/results.md#a-common-error-boundary); [compiled errors and generic patterns](../../tests/e2e/testdata/accept/library-errors.ms).
Verify: exact nominal identities and generic arguments determine a match; the receiver and payload survive conversion and propagation; missing implementations, incomplete generic patterns, and missing fallbacks are rejected.
