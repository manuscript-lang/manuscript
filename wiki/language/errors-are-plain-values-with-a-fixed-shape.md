[Wiki](../index.md) › [Language](index.md)

# Errors are plain values with a fixed shape

Decision (2026-11-01): the owner replaced per-domain error types, narrowing and the `Error` interface with one prelude record, `Error(message, kind: String? = none, details: Map[String, String] = {})`, built like any record (Go's `errors.New`). Callers branch on `kind` and read `details`; they import no domain type. `T!` is `Result[T, Error]`. `try` needs the identical error type, so a custom `E` converts by an ordinary function or `map_error`. No cause chain yet; add one when a stdlib site needs it.

Apply when: adding a fallible stdlib API, a native adapter, or an error example.
Evidence: [Error](../../stdlib/core.ms), [results guide](../../documentation/core-language/errors/results.md), [library errors](../../tests/e2e/testdata/accept/library-errors.ms), [proposal](../../proposals/error-values.md).
Verify: a missing file yields `kind == "ENOENT"` with no import; two equal `Error` values compare equal; native statuses become `Error` in lowering (`status_table`, `domain_of`), and a status with no row falls back to `EIO`.
Pitfalls: defaults on bundled prelude records must use forms `literal_default` accepts (`none`, `Map[String, String]()`); an unqualified case such as `Closed` is ambiguous when another alternative in scope has it, so write `"EBADF"`; stdlib is embedded at build time, so rebuild `ms` before rerunning fixtures.


Update (2026-11-04): the owner replaced the closed `ErrorCategory` enum with a short string `kind` so users can define their own kinds, and made it optional (`String?`, default `none`), and asked that the stdlib report standard errno codes (`ENOENT`, `EBUSY`). Codes of at most 15 bytes are inline and never allocate. Mapping and rationale: [proposal](../../proposals/error-kind-string.md); `rtcall::status_table` is the single native status-to-code table. Parse and limit failures with no natural errno use `EBADMSG` and `EOVERFLOW`.
