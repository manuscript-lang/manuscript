[Wiki](../index.md) › [Language](index.md)

# Invalid bounds must not survive recovery

Verified (a Go-era crash class; the invariant is language-level): reporting an invalid bound without removing it lets implementation substitution turn a variable bound into a self-referential graph. Diagnostic hints and editor member discovery must terminate even on malformed bound graphs. Keep valid interface bounds such as `T: Compare[T]`; reject variable bounds such as `T: T` without attaching them as evidence.

Verified: interface operations and implementation methods need the same bound validation as named declarations. Their former separate resolution paths accepted bounds such as `T: Int`. The shared validator now rejects these before attaching evidence; [operation-bound regressions](../../crates/ms-check/src/operation_bounds_tests.rs) cover explicit interfaces, implementations, inherent methods, and preservation of valid recursive bounds.

Apply when: resolving generic bounds, copying implementation variables, or traversing recovered types for diagnostics and editor queries.
Evidence: [recursive interface bound fixture](../../tests/conformance/fixtures/e2e/accept/recursive-interface-bound.ms).
Verify: a program with `T: T` reports a diagnostic and the checker and language server both terminate.

Register nominal generic parameter lists before resolving any declaration bounds, including across a bundled module group. Otherwise a forward `Reader[Int]` bound sees zero parameters, while a missing required argument can pass silently. Resolve bounds before defaults because deferred default validation snapshots them. The [declaration-order regressions](../../crates/ms-check/tests/operation_bounds/declaration_order.ms) and [arity rejections](../../crates/ms-check/tests/operation_bounds/declaration_arity.ms) cover both orders (#3489).

Default type arguments also need bound checks on their nested applications, even when the parameter has no explicit bound. Resolve them with earlier parameters and the enclosing receiver scope; validate after record fields and local implementations are complete. Substitute the default into recursive bounds and receiver bindings into method defaults without mutating shared variables. The [type-default regressions](../../crates/ms-check/src/type_argument_defaults_tests.rs) cover these paths and rejection controls.

Default recovery can leave holes in a parameter list, including a later default that failed to resolve. Compute minimum positional arity through the last parameter without a resolved default; the first default does not prove the remaining suffix can be omitted. Otherwise an already-diagnosed declaration such as `type Broken[A = Int, B]` can panic when a type annotation or application omits `B` (#3261).
