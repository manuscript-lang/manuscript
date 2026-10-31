[Wiki](../index.md) › [Standard-library design](index.md)

# Fallible APIs return domain errors that implement Error

Decision: `Result[T, E: Error]`; plain text uses the flat record `TextError("message")` (one `text` field, not a one-case alternative); domain packages define their own error types with `impl Error`. No `Result[T, String]` anywhere, including docs and fixtures.


Apply when: writing a Result-returning API, example, or test.
Evidence: [core.ms](../../stdlib/core.ms), [core.ms](../../stdlib/core.ms), commit fd5b0bf9; see also the Result bound entry in [language.md](../language/index.md).
Verify: `Result[Int, String]` is rejected; `TextError("x").text == "x"`.
