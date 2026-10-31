[Wiki](../index.md) › [Language](index.md)

# Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. A source function's default is evaluated in the callee's scope, so it can read earlier parameters.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [native default behavior](../../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.
