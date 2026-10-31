[Wiki](../index.md) › [Testing and conformance](index.md)

# Fixtures follow current idiom, except where they test the old form

Decision: after sweeping renames (`to_string`, positional arguments, `--drop-labels`, `get(default)`, `TextError`, `write_bytes`, no `->`), fixtures are migrated to the new spelling; only rejected-variant fixtures keep removed syntax, and only to assert the diagnostic. A fixture that uses a removed name to pass is a stale test, not a compatibility contract. Accepted fixtures keep some/none `match` only when testing match semantics; nested `match` is guarded by `make repo-check`.

Apply when: a rename or removal lands, or a rebase brings in fixtures written before it.
Evidence: [nested-match check](../../crates/ms-repo-check/src/nested.rs); `ms-repo-check` skips `tests/conformance/fixtures/` because those inputs are frozen.
Verify: `rg` for the old spelling finds only reject fixtures and intentionally scoped allowances.

---
Topics: [Testing](../topics/testing.md)
