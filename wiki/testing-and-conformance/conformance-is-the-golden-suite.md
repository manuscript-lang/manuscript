[Wiki](../index.md) › [Testing and conformance](index.md)

# Conformance is the golden suite

Decision (Chinmay, 2026-11-11): the conformance corpus is the one golden test suite for Manuscript behavior. Rust tests cover Rust constructs; Manuscript code is tested in `.ms`, never in Rust strings. Where an `.ms` fixture already exercises the code, retire the crate-specific Rust test that duplicates it, since it only costs CPU.

- `ms-conform` is the one runner (`make test`); e2e data belongs in conformance. Unify first, then optimize.
- A faulting test runs inside a promise, not a fork, so every platform behaves the same; only a few tests spawn a process to check exit-on-fault.
- Every bug fix lands with a regression test at the layer that fails for the right reason ([choose the layer](choose-the-layer-that-can-fail-for-the-right-reason.md)).

- Order events with real synchronization, never random sleeps. Run tests on Debug (Cranelift) builds; a platform-sensitive test is verified on macOS and Windows before the fix is called done.

Apply when: adding a test or moving coverage between layers.
Evidence: [pull request CI budget](../repository/pull-request-ci-has-a-five-minute-budget.md).
