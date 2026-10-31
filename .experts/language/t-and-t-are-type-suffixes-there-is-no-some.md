[Wiki](../index.md) › [Language](index.md)

# `T!` and `T?` are type suffixes; there is no `some`

Decision (Chinmay): `T!` is `Result[T, Error]` and `T!E` is `Result[T, E]` (no space before `E`), mirroring `T?` for optionals. Both are parser sugar, so the checker and diagnostics see the same `Named` type; `Result[T, E]` stays valid. `T?` is the only optional spelling: a plain `T` converts where `T?` is expected, `some(...)` is rejected, a `T?` parameter or field defaults to `none`, and `a?.b` chains through optionals.

Apply when: writing signatures, examples, stdlib code, or changing type-suffix parsing. Use `X!` rather than `Result[X, Error]` in new code.
Evidence: [results](../../documentation/core-language/errors/results.md), [optionals](../../documentation/core-language/types/optionals.md), [result-shorthand proposal](../../proposals/result-shorthand.md), [optional-ergonomics proposal](../../proposals/optional-ergonomics.md).
Verify: `Int!` and `Result[Int, Error]` are interchangeable; `some(1)` is rejected.

---
Topics: [Optionals](../topics/optionals.md) · [Errors and results](../topics/errors-and-results.md)
