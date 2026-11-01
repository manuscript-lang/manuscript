[Wiki](../index.md) › [Language](index.md)

# Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. A source function's default is evaluated in the callee's scope, so it can read earlier parameters.

Verified: an interface operation's `T? = none` default needs both the interface and operation type parameters in scope. Reuse the operation's resolved variables when checking defaults; redeclaring them can replace the identities already used by its signature. The [generic-default regressions](../../crates/ms-check/src/generic_defaults_tests.rs) cover explicit and implicit defaults, inferred calls, and scope isolation.

Verified: lowering must distinguish a substituted Optional payload from the extra Optional layer used for omission. Comparing a generic binding's unsubstituted name to its machine type rejects valid Optional callbacks; omitting the extra layer for defaulted Optional parameters collapses omission and an explicitly supplied `none`. The [generic Optional callback regressions](../../tests/e2e/testdata/accept/generic-optional-callbacks.ms) exercise both, including nested Optionals, default-aware callables and required function types.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [native default behavior](../../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.
