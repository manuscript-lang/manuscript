[Wiki](../index.md) › [Language](index.md)

# Default arguments must not leak across callable replacement

Decision: ordinary record fields may have default expressions. Constructors evaluate supplied arguments before omitted defaults in field order, with earlier fields available to later defaults; explicit values skip defaults and each construction evaluates fresh storage. A source function's default is evaluated in the callee's scope, so it can read earlier parameters. The user explicitly requires standard runtime functions to appear as syntactically correct empty functions, with their full declarations and ordinary colon headers; do not introduce a `native` keyword or hide invalid syntax in editor analysis. Evidence: [record construction rules](../../documentation/core-language/types/records.md#construction), [field-default conformance](../../tests/e2e/testdata/accept/field-defaults.ms).

Verified: defaults are permissions on a known callable, not part of function-type identity. Retaining that permission on a mutable binding or inferred generic type could let a required-argument function replace a defaulted function, then be called with a missing argument. Explicit function types, mutable bindings, and generic inference erase defaults; inferred immutable copies retain them.

Apply when: changing callable metadata, assignment, generic inference, default arguments, or function-value tooling.
Evidence: [canonical default rules](../../documentation/core-language/functions/declarations-and-calls.md#default-arguments); [native default behavior](../../tests/e2e/testdata/accept/default-arguments.ms).
Verify: replace a defaulted function with a required-argument function through a mutable binding and reject omission; reject omission after generic forwarding, while an inferred immutable copy still accepts it.

---
Topics: [Errors and results](../topics/errors-and-results.md) · [Types and interfaces](../topics/types-and-interfaces.md)
