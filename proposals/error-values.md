# Errors are plain values

## Summary

- Problem: a failure is a domain type (44 in `stdlib/`, each with cases, payloads and `impl Error`) that callers import, narrow with `match`, and convert at `Error` boundaries by interface dispatch.
- Change: one fixed prelude record `Error` with `message`, a `kind` from `ErrorCategory`, and `details`. Built like any record: `Error("file not found", kind: NotFound)`, Go's `errors.New`.
- Shipped in one PR with no bridge: the domain types, the `Error` interface, `TextError`, `MissingValue`, `category()`, narrowing and the checker and lowering boundary machinery are deleted together.

## Status

Implemented, 2026-11-01. Direction (Chinmay): "let's revamp the error mechanism in manuscript, instead of case classes. and narrowing etc, let's make simple values with fixed structure, where we can keep a field for storing additional details and go style thing of error.New", then "do all in one pr". Builds on the 2026-10-31 decision that `Result[T, E]` takes any `E`.

## Problem

```manuscript
fn handle(cause: Error) String:
    match cause:                            # contract type pattern: narrowing
        IoError(e): return "io {e.message()}"
        _: return cause.message()
```

- 44 error types, 134 conformance files with `impl Error for`, about 1000 mentions of `*Error.Case` in tests and docs.
- The checker and lowering carry interface boxing for `Error` (`error_assignable`, `error_needs_scope`, `scoped_error`, `category.rs`, `messages.rs`) that exists only to hide the domain type.
- A caller that only cares "not found or denied" still imports the domain type, and `category(cause)` recovers that by a table lookup.

## Design

```manuscript
# prelude
export type Error:
    message: String
    kind: ErrorCategory = ErrorCategory.Other
    details: Map[String, String] = Map[String, String]()
```

- `Error("bad port")`, `Error("no such file", kind: NotFound, details: {"path": path})`. No new syntax, static method or namespace.
- `T!` stays `Result[T, Error]`. `try` needs the identical error type, so there is no implicit widening; a custom `E` converts with an ordinary function or `map_error`. Custom `E` stays legal.
- `ErrorCategory` is a prelude alternative with 13 cases, including `Other` (the default) and `Failed`. `category()` becomes the field.
- `details` is `Map[String, String]`: printable, comparable and owned by the error. Structured payloads are out of scope.
- Native statuses become `Error` records in lowering: the status maps to a kind and the domain words come from the symbol prefix (`status_table`, `domain_of`). Callbacks into the runtime map back through `error_status` with ordinal tables. Status codes are unchanged.
- Helpers replace deleted constructors where a package built the same error repeatedly (`yaml_invalid`, `cli_*`, `not_started`).
- `Optional.ok_or()` builds an `Error` of kind `NotFound` with the source location.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms` and 40 stdlib files | `Error` record, `ErrorCategory`, domain types and `impl Error` removed | `tests/e2e/testdata/stdlib/error-categories.ms` |
| `ms-check` | prelude names, `try` identical-type rule, boundary machinery deleted | conformance `accept` and `reject` |
| `ms-lower` | `Error` built from status; `category.rs`, `messages.rs` deleted | `crates/ms-build/tests/lower` |
| tests, docs, wiki | migrated to `kind` and `details` | `make repo-check`, e2e, conform |

## Alternatives

- Do nothing: keeps typed errors; costs the boundary machinery and an import per failure.
- Staged bridge (`Reportable` plus package-by-package PRs): rejected by the owner; a bridge exists only to be deleted.
- `details: Any` or JSON: needs a dynamic value type the prelude lacks; strings cover paths, codes and operations.
- `kind: String`: no exhaustive set, typos compile. The enum already existed.
- Cause chain (`cause: Error?`, Go's `%w`): deferred. Add when a stdlib site needs it; #2287's `wrap` and `join` are the first candidate and fold into this record.

## Open questions

- Should `details` hold `Json` once a use needs numbers or nesting?
- Is 13 categories enough, or do host errors need `Interrupted` or `Busy`?
