# Structured errors

## Summary

- Problem: an `Error` value cannot be logged as data, so agents reading logs get only `message()` text.
- Change: one stdlib function, `error_record`, plus logger calls that take an error. No new syntax, no vtable lowering.
- Decision requested: the open questions below.

## Status

Proposal, 2026-11-01, checked against f17aecf9. Supersedes the `standard_message` helper (dropped) and a draft with a vtable-driven `describe` and body-less `impl Error` (skeptic: infeasible lowering, grammar change, leak by default). Review of this version: pending.

## Problem

- `log_with[F: Data]` already accepts a concrete error enum (Data when every field is), so `logger.error_with("open failed", err)` works, but the record has no stable shape and no `message()`.
- Once an error is erased to `Error` (`T!`), `Data` no longer applies and only `err.message()` can be logged.

## Design

```manuscript
# Record for logs: {"error": type name, "value": <stringify encoding>, "message": cause.message()}.
export fn error_record[E: Error + Data](cause: E) JsonValue: ...
```

- Written in `.ms` on top of `stringify`, so `value` has exactly the shape `parse` round-trips. The only primitive needed is the type's qualified name (module path included, so two `ConfigError` types do not collide).
- `Logger.error_with(message, cause)` and `warn_with` take `E: Error + Data` and add `"err": error_record(cause)` to the record.
- Payloads are logged by default; an author who must hide a field keeps it out of the error type. State this in the docs, since `Failed(message)` can name paths.
- If encoding fails or exceeds limits, `error_with` returns the same `InvalidData`/`LimitExceeded` as `log_with`.
- A non-`Data` error is a compile error at the call, not a silent downgrade; log `err.message()` instead.
- `message()` stays explicit. Glue in stdlib enums is left alone.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms` | `error_record`, type-name primitive | stdlib e2e on a stdlib and a user error |
| `stdlib/log.ms` | `error_with`, `warn_with` (after #2184) | logger e2e: record keys, nested cause |
| `documentation/` | errors guide: logging an error | `make repo-check` |

## Alternatives

- Do nothing: callers log `message()` only.
- Vtable-driven `describe(Error)`: covers erased errors but needs the checker type at the MIR layer and a new encoder case for interface values (`json.ms` never encodes them); rejected.
- Body-less `impl Error` with a default message: grammar change and a contracts.md exception for little gain; rejected.

## Open questions

- Measure how often callers hold erased `Error` versus a concrete `E` before adding anything for the erased case. Recommendation: ship the concrete-`E` version first.
- Schema keys (`err`, `error`, `value`, `message`) become public log schema. Recommendation: accept.
