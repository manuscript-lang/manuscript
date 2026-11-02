[Wiki](../index.md) › [Language](index.md)

# Error translation does not need a dedicated standard helper

Decision: remove the specialized Result error-mapping helper and keep domain translation in ordinary functions that test `is_error()` and read `err()`, never a `match`. The newer error simplification permits specific errors to pass directly into the standard Error boundary, including through `try`; unrelated domain errors still require explicit translation. Do not restore a dedicated mapping helper.

Apply when: adding Result adapters or rewriting examples that combine execution and domain errors.
Evidence: [flat flow and grammar compatibility](../../documentation/core-language/control-flow/pattern-matching.md#keep-match-flow-flat); [error compatibility](../../documentation/core-language/errors/propagation.md#error-compatibility).
Verify: examples compile with compatible `try` calls and introduce only the concepts they teach. Result's success-only `map` and same-error `and_then` retain the original error payload; they do not add an error-translation helper.
