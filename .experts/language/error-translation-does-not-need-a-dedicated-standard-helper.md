[Wiki](../index.md) › [Language](index.md)

# Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep domain translation in ordinary functions that test `is_error()` and read `err()`, never a `match`. The newer error simplification permits specific errors to pass directly into the standard Error boundary, including through `try`; unrelated domain errors still require explicit translation. Do not restore a dedicated mapping helper.

Decision: the user requested "please remove nested match from everywhere, note it as anti pattern and ensure it never gets repeated", then reaffirmed "nested match is anti pattern, solve it another way". This includes implementation, examples, documentation and diagnostic remedies. Keep grammar and execution semantics available for compatibility and meaningful syntax/semantic regressions. Use compatible `try`, early-exit payload bindings, Optional methods, or small helpers; the user also rejected elaborate loading examples, so avoid contrived domain models and helper layers added only to make an example work.

Verified: MSL107 warns at each structurally inner match ([match lint](../../crates/ms-tooling/src/lint/matches.rs)); the [repository guard](../../crates/ms-repo-check/src/nested.rs) inspects sources and Markdown fences, and test allowances are scoped and require a reason. MSL106 belongs to the payload-binding rule ([binding lint](../../crates/ms-tooling/src/lint/bindings.rs)); take new rule codes from the actual lint registry, not from an earlier completion report.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: [flat flow and grammar compatibility](../../documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat); [error compatibility](../../documentation/core-language/errors/propagation.md#error-compatibility).
Verify: examples compile with compatible `try` calls and introduce only the concepts they teach. Result's success-only `map` and same-error `and_then` retain the original error payload; they do not add an error-translation helper. The standard Result module exports only its type, and regenerated API references agree with its declarations. [Called composition tests](../../tests/e2e/testdata/stdlib/core-parity.ms) distinguish success transformation from error translation.

---
Topics: [Errors and results](../topics/errors-and-results.md) · [Diagnostics and tooling](../topics/diagnostics-and-tooling.md)
