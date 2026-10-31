[Wiki](../index.md) › [Testing and conformance](index.md)

# Conformance expectations are frozen contracts

Decision: the corpus expectations were first recorded from the Go `ms` and are now the contract; the Go implementation is gone and is not needed to extend them. Known differences of the Rust `ms` are listed in `tests/conformance/expect-fail.txt` with a reason, and fixtures tagged `aliasing` are excluded because the value-semantics migration changes them on purpose. Remove an expect-fail entry when it is fixed; do not add one to hide a new regression.

Apply when: a conformance case fails, or a deliberate semantic change alters recorded output.
Evidence: [corpus README](../../tests/conformance/README.md), [expected failures](../../tests/conformance/expect-fail.txt), [runner](../../crates/ms-conform/src/runner.rs).
Verify: `make conform` reports a nonempty plan with no unexpected failures or unexpected passes.

---
Topics: [Testing](../topics/testing.md) · [Types and interfaces](../topics/types-and-interfaces.md)
