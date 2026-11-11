[Wiki](../index.md) › [Compiler and build](index.md)

# Callback adapters do not change generic type identity

Verified: a reader may adapt to an outer `fn(var T) U` parameter, but that conversion must not recurse into nominal arguments or a callable's parameter/result types. Otherwise an implementation for `Box[fn(var Int) Int]` incorrectly supplies methods on `Box[fn(Int) Int]`. Overlap matching must compare callback `var` modes and ignore parameter names, just like type identity; fixing overlap alone exposes wrong dispatch through the permissive receiver matcher (#3359).

Apply when: changing structural unification, implementation overlap, method lookup, or interface vtables.
Evidence: [function type identity](../../documentation/core-language/functions/function-values-and-closures.md#function-type-compatibility), [checker regressions](../../crates/ms-check/tests/callback_identity.rs), [called dispatch regression](../../tests/conformance/fixtures/e2e/accept/callback-implementation-identity.ms).
Verify: distinct callback specializations dispatch correctly in either declaration order through direct calls, generic bounds, views and method values; a sole mismatched implementation is rejected; direct reader adapters still execute.
