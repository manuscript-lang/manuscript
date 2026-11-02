[Wiki](../index.md) › [Language](index.md)

# No special `get` accessor declarations

Decision: the user rejected the `get name -> Type` accessor syntax merged in #516 (2026-10-16) and asked for ordinary members: observational reads such as `length` are methods called as `items.length()`. Do not reintroduce a second member category, contextual keyword, or accessor-specific dispatch without a new decision. The speed motivation is met in lowering instead: a List or Bytes `length()` call is lowered directly rather than through a runtime call.

Apply when: proposing property-like syntax, a read-only member kind, or a standard-library migration from methods to properties.
Apply when: changing Optional declarations, alternative method lookup, fallback evaluation, or introductory examples.
Evidence: [native member lowering](../../crates/ms-lower/src/native.rs), which special-cases `length` on List and Bytes.
Evidence: [if let rules](../../documentation/core-language/control-flow/conditionals.md#unwrapping-an-optional-or-result), [if let fixture](../../tests/conformance/fixtures/e2e/accept/if-let.ms), [two-arm match lint](../../crates/ms-tooling/src/lint/matches.rs), [Optional contract](../../documentation/core-language/types/optionals.md#checking-and-extracting-values), [optional argument rules](../../documentation/core-language/types/optionals.md#passing-optional-arguments), [canonical declaration](../../stdlib/core.ms), [method fixture](../../tests/e2e/testdata/accept/optional-methods.ms), [argument fixture](../../tests/conformance/fixtures/e2e/accept/optional-arguments.ms).
Verify: `get` is an ordinary identifier everywhere; a List `length()` call involves no runtime function call.
Verify: false and zero are present; eager `get(default)` values evaluate normally; `or_else` callbacks run exactly once only for none; `get()` with no default on none or error faults clearly.
