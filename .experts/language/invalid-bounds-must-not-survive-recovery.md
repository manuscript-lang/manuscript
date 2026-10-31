[Wiki](../index.md) › [Language](index.md)

# Invalid bounds must not survive recovery

Verified (a Go-era crash class; the invariant is language-level): reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph. Diagnostic hints and editor member discovery must terminate even on malformed bound graphs. Keep valid interface bounds such as `T: Compare[T]`; reject variable bounds such as `T: T` without attaching them as evidence.

Apply when: resolving generic bounds, copying implementation variables, or traversing recovered types for diagnostics and editor queries.
Evidence: [recursive interface bound fixture](../../tests/e2e/testdata/accept/recursive-interface-bound.ms).
Verify: a program with `T: T` reports a diagnostic and the checker and language server both terminate.
