[Wiki](../index.md) › [Language](index.md)

# Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. A source function's default is evaluated in the callee's scope, so it can read earlier parameters.

Verified: an interface operation's `T? = none` default needs both the interface and operation type parameters in scope. Reuse the operation's resolved variables when checking defaults; redeclaring them can replace the identities already used by its signature. The [generic-default regressions](../../crates/ms-check/src/generic_defaults_tests.rs) cover explicit and implicit defaults, inferred calls, and scope isolation.

Verified: lowering must distinguish a substituted Optional payload from the extra Optional layer used for omission. Comparing a generic binding's unsubstituted name to its machine type rejects valid Optional callbacks; omitting the extra layer for defaulted Optional parameters collapses omission and an explicitly supplied `none`. Bound native thunks must first instantiate the method's declared signature from its checked function-value type; otherwise adaptation can try to lower an unresolved method variable. The [generic Optional callback regressions](../../tests/e2e/testdata/accept/generic-optional-callbacks.ms) exercise these cases, including nested Optionals, default-aware callables and required function types.

Verified: a bound `ok_or[MissingValue]` needs its invocation's position, which a shared native thunk cannot recover from its binding. Its checked omission metadata marks this native default; immutable copies and substitution retain it, while required callable conversions erase permission and origin together. Callers prepare the omitted cause using normal owned argument temporaries; supplied `none` bypasses generation, and ordinary/interface defaults carry no native marker. The [exact-line fixture](../../tests/e2e/testdata/accept/bound-missing-value-source.ms) and [cross-file fixture](../../tests/e2e/testdata/projects/bound_missing_value/conformance_test.ms) pin invocation attribution without runtime context or ABI changes.

Native/interface adapters keep Optional argument selections borrowed when the default is only `none`; the called operation makes any required owned result. Copying that selection eagerly charges ignored arguments for ownership adaptation. The [heap-backed argument regressions](../../tests/e2e/testdata/accept/native-optional-default-borrows.ms) pin temporary survival and independent results without changing source-lambda default ownership.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [native default behavior](../../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.
