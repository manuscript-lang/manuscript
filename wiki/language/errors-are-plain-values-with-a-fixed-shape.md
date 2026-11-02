[Wiki](../index.md) › [Language](index.md)

# Errors are plain values with a fixed shape

Decision (2026-11-01): the owner replaced per-domain error types, narrowing and the `Error` interface with one prelude record, `Error(message, kind: ErrorCategory = Other, details: Map[String, String] = {})`, built like any record (Go's `errors.New`). Callers branch on `kind` and read `details`; they import no domain type. `T!` is `Result[T, Error]`. `try` needs the identical error type, so a custom `E` converts by an ordinary function or `map_error`. No cause chain yet; add one when a stdlib site needs it.

Apply when: adding a fallible stdlib API, a native adapter, or an error example.
Evidence: [Error and ErrorCategory](../../stdlib/core.ms), [results guide](../../documentation/core-language/errors/results.md), [library errors](../../tests/e2e/testdata/accept/library-errors.ms), [proposal](../../proposals/error-values.md).
Verify: a missing file yields `kind == NotFound` with no import; two equal `Error` values compare equal; native statuses become `Error` in lowering (`status_table`, `domain_of`), and an unknown kind falls back to `Other`.
Pitfalls: defaults on bundled prelude records must use forms `literal_default` accepts (`ErrorCategory.Other`, `Map[String, String]()`); an unqualified case such as `Closed` is ambiguous when another alternative in scope has it, so write `ErrorCategory.Closed`; stdlib is embedded at build time, so rebuild `ms` before rerunning fixtures.
