# Standard error messages

## Summary

- Problem: 37 hand-written `impl Error` matches in `stdlib/` repeat the same standard-case texts per enum (`"<prefix>: invalid input"`).
- Change: one stdlib function, `standard_message(prefix, cause)`, in `stdlib/core.ms`, written in Manuscript on top of the existing `category`. No new syntax, type, or Rust.
- Decision requested: approve the helper, and whether to normalize message texts (open question).

## Status

Proposal, 2026-11-01, checked against f17aecf9. Skeptic review: drop the runtime helper (about 50 net lines saved, payload fallthrough can silently drop text, wording is duplicated in `messages.rs` and `ms-std-net`); prefer a repo-check lint or extending the `messages.rs` table.

## Problem

`log.ms` today (9 lines for what is one rule):

```manuscript
impl Error for LogError:
    fn message() String:
        match self:
            InvalidInput: return "logging: invalid input"
            InvalidData: return "logging: invalid data"
            LimitExceeded: return "logging: limit exceeded"
            Closed: return "logging: resource is closed"
            Io(cause): return cause.message()
            FileSystem(cause): return cause.message()
```

- About 22 of 37 matches are this shape: standard-named cases formatted as `prefix: text`, plus payload cases that only forward.
- The standard names are already a closed list in `ErrorCategory`, and `category(cause)` already maps a standard case to it by name (`crates/ms-lower/src/category.rs`).
- The same text is written 20+ times with drift ("resource is closed" vs "closed", "TLS:" vs "tls:").

## Design

Add to `core.ms`:

```manuscript
# "<prefix>: <text for category(cause)>"; "<prefix>: error" when the case has no standard category.
export fn standard_message(prefix: String, cause: Error) String: ...
```

Body is Manuscript: `category(cause)`, then a flat `match` of `ErrorCategory` to text, so the wording lives in one place. Use:

```manuscript
impl Error for LogError:
    fn message() String:
        match self:
            Io(cause): return cause.message()
            FileSystem(cause): return cause.message()
            _: return standard_message("logging", self)
```

- Standard cases drop out; only payload-bearing or domain cases remain in the match.
- Cases with no category (`Failed(message)`, `OutOfRange`, `Status(code)`) stay explicit, so every domain text is still visible where the type is defined.
- `Failed(message): return message.clone()` is one line and stays; a second helper is not worth it.
- Forwarding lines (`Io(cause)`) stay. Removing them needs reflection or syntax; see Alternatives.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms` | add `standard_message` | conformance fixture: every `ErrorCategory` yields its text |
| stdlib `impl Error` blocks | replace standard-case lines | existing message assertions, updated where wording normalizes |
| `documentation/core-language/errors/` | one paragraph on the helper | `make repo-check` |

## Alternatives

- Do nothing: the cost is ~100 duplicated lines and drifting wording; no behavior risk.
- `derives "prefix"` clause on `impl` (new syntax, compiler-generated): removes forwarding lines too, but adds syntax and an all-or-nothing rule; rejected as ugly by the user.
- Default method on `Error`: the language has no default method bodies; adding them is a far larger change.
- Per-case message text on the declaration: touches every case declaration and needs new syntax.

## Open questions

- Normalize wording to one text per category ("resource is closed", "operation not supported")? Recommendation: yes; a few messages change in diagnostics only, and the conformance fixtures are updated in the same PR.
- Should payload cases that are `Error`-typed (`Io(cause)`) be forwarded automatically? Recommendation: no; it needs reflection and the lines are short.
