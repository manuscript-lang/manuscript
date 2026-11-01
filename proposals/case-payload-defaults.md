# Case payload defaults and shared case fields

## Summary

- Problem: each stdlib `Error` enum repeats a `match` whose arms are fixed message strings, far from the case they describe (37 impls; `log.ms:314`).
- Change: two general rules, no error-specific syntax: a case payload field may have a default (as a record field does), and a field that every case declares with the same name and type is readable on the alternative.
- Decision requested: approve both rules; the `case` keyword is unchanged.

## Status

Proposal, 2026-11-01, checked against f17aecf9. Earlier drafts (`standard_message` helper, `error_record`, `kind` record, body-less `impl Error`) were dropped; the user rejected `kind` and `=` after the case. Skeptic review: drop. A defaulted payload turns unit cases into call syntax (breaking about 270 call and match sites), grows every value of the type, allocates per error, and needs JSON-decode changes (`json.rs:686`). Net savings are about zero (19 pure impls, 43 total, not 37). Keep only the shared-field read, if anything.

## Problem

`LogError` states each text twice, in the case list and in a nine-line match (`stdlib/log.ms:314`). The texts drift between enums, and a logged error carries only `message()` output, not a field an agent can read.

Both rules are rejected today (`ms check` at f17aecf9):

```manuscript
type E:
    case Closed(message: String = "closed")
# parse: function types and case payloads cannot have defaults; put the default on a named
# function parameter or a record field instead

fn f(e: E) Int:
    return e.code
# resolution: unknown or ambiguous member code on E; this type has no fields or operations
```

## Design

1. **Payload defaults.** `case Name(field: T = expr)` uses the record rule in `records.md`: an omitted field takes the default, evaluated per construction, and a default may use earlier payload fields of that case and module declarations. Any supplied value skips it. `alternatives.md` ("fields have no defaults") changes to point at the record rule.
2. **Shared field read.** If every case of an alternative declares field `x` with the same type, `value.x` reads it. Otherwise the existing diagnostic stays. A read follows the record ownership rules: moving it out of `self` needs `.clone()`.

```manuscript
type LogError:
    case Closed(message: String = "logging: resource is closed")
    case InvalidInput(message: String = "logging: invalid input")
    case Io(cause: IoError, message: String = cause.message())

impl Error for LogError:
    fn message() String:
        return self.message.clone()
```

- `LogError.Closed` and `LogError.Io(cause)` construct as before; callers may pass `message:` to override the text.
- `match` and `if let` on cases are unchanged; the field is also an ordinary payload field in patterns.
- The impl stays one fixed line. Removing it needs `Error`-specific behavior, which review and the user's goal (general primitives) argue against.
- Wiring-level logging gains a stable `message` key: `stringify(err)` already includes payload fields for a `Data` error.
- A field and a method may share the name `message`: records already allow it (verified: `type R: message: String` with `fn message()` checks).

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-syntax` | accept `= expr` in case payload fields | parser accept case, existing reject case removed |
| `crates/ms-check` | check defaults like record defaults; shared-field member lookup | conformance accept and reject (types differ, one case lacks it) |
| `crates/ms-lower` | fill omitted payload defaults; shared-field read through the tag | e2e on native build |
| `stdlib/*.ms` | migrate pure-standard errors, keep domain texts | existing message assertions; same strings |
| `documentation/core-language/types/` | alternatives and records pages | `make repo-check` |

## Alternatives

- Do nothing: about 100 duplicated lines and drifting wording.
- Helper `standard_message(prefix, self)`: about 50 lines saved, silently drops payloads on `_:`, and the wording is also copied in `messages.rs`; dropped by review.
- Error as record with `kind`: loses exhaustive matching and typed payloads; rejected by the user.
- Body-less `impl Error` default message: grammar change and a contracts exception.

## Stages

1. Payload defaults, with checker, lowering and docs; one stdlib type as proof (not `log.ms` until #2184 lands).
2. Shared-field read.
3. Migrate stdlib errors; texts unchanged, so no fixture churn.

## Open questions

- Should a shared field be required to have an identical default in every case? Recommendation: no; defaults are per case.
- Migrate all 37 impls, or only pure-standard ones? Recommendation: pure-standard ones, keeping domain text visible in the match.
