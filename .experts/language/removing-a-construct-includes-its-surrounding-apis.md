[Wiki](../index.md) › [Language](index.md)

# Removing a construct includes its surrounding APIs

Decision: the request to remove `assert` required follow-up corrections to remove assertion helpers, bindings, docs, and even residual tests. The user wanted ordinary `if`/`return` control flow. Removing the syntax alone did not satisfy the requested surface.

Apply when: removing or renaming language constructs or standard APIs.
Evidence: none recorded.
Verify: inventory related exported helpers and aliases before editing, regenerate references, then check every surface covered by the removal request. Follow an explicit zero-reference request when deciding whether rejection tests should retain the old spelling.

Verified: when rebasing standard-library work onto current main, migrate new conformance fixtures and documentation examples to ordinary `if not (...)` checks returning `panic`; do not restore the removed testing module or its native bindings from a stash. The source-level [built-in parity fixture](../../tests/e2e/testdata/accept/builtin-parity.ms) exercises this form, and [standard declarations](../../stdlib/test.ms) remain free of the removed module.

---
Topics: [Testing](../topics/testing.md)
