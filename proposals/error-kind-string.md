# Error kind as a short string

## Summary

- `Error.kind` is a closed `ErrorCategory` enum, so a library cannot add its own kind and callers cannot match a kind they did not import.
- Make `kind` a `String` holding a short errno-style code (`"ENOENT"`, `"EBUSY"`); the stdlib reports standard codes.
- Decision requested: none; this is the owner's direction.

## Status

Approved 2026-11-04. Owner: "make kind a string and rework the internals of standard lib to return standard error code such as enoEnt or ebusy". Checked against `b55e66d6`.

## Problem

`stdlib/core.ms` fixes 13 kinds. `Error("limit hit", kind: ...)` cannot name anything else, and a user package must overload `Other` and put its own tag in `message` or `details`.

```ms
// today: rejected, no such case
return error(Error("quota exceeded", kind: ErrorCategory.QuotaExceeded))
```

## Design

```ms
export type Error:
    message: String
    kind: String = "EUNKNOWN"
    details: Map[String, String] = Map[String, String]()

fn open_config(path: String) String!:
    return error(Error("no config", kind: "ENOENT", details: {"path": path}))
```

- A kind is any short string; the convention is an uppercase code. `ErrorCategory` is removed; there is no replacement type.
- The stdlib uses POSIX errno names where one fits, so `kind == "ENOENT"` is the same test as on a Unix system on every platform.
- User kinds use their own prefix, for example `"EQUOTA"`; stdlib never adds a code outside the table.
- `wrap_error` keeps the kind; `Error` equality compares the string.
- The kind itself never allocates: a literal is a static string and any string of at most 15 bytes is stored inline in the two words (`crates/DESIGN.md`), so building, cloning and comparing a code allocates nothing (the `details` map default is unchanged). A code longer than 15 bytes costs one allocation when cloned; the stdlib codes are all shorter.
- Comparing a mistyped code is silent. The stdlib guide lists every code; a checker lint is out of scope.

Mapping from the old cases (`status_table` rows keep their numbers):

| Old kind | Code |
| --- | --- |
| InvalidInput | `EINVAL` |
| InvalidData | `EBADMSG` |
| LimitExceeded | `EOVERFLOW` |
| OutOfRange | `ERANGE` |
| NotFound | `ENOENT` |
| AlreadyExists | `EEXIST` |
| directory not empty (was Other) | `ENOTEMPTY` |
| PermissionDenied | `EACCES` |
| Unsupported | `ENOTSUP` (`ENOTTY` for not a terminal) |
| Closed | `EBADF` |
| Failed | `EIO` |
| Unavailable | `EAGAIN` (`EBUSY` for a busy terminal) |
| Timeout | `ETIMEDOUT` |
| Other | `EUNKNOWN` (`EAUTH` for failed authentication) |

- Two limit statuses (3 and 14) share `EOVERFLOW`; the message tells them apart.
- `EAUTH` and `EUNKNOWN` are not POSIX names; they are Manuscript's own.
- The native ABI is unchanged: statuses stay `u8`; lowering maps a status to its code string.
- `std/http` serving still maps a handler error to a status by comparing the kind string.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/*.ms` | `kind: ErrorCategory.X` becomes the code literal | `tests/e2e/testdata/stdlib/error-categories.ms` |
| `crates/ms-lower` (`rtcall.rs`, `httpserve.rs`, `json.rs`, `native.rs`) | build the `Error` with a string kind; compare strings | e2e fixtures, lower tests |
| `crates/ms-check/src/stdlib.rs` | drop `ErrorCategory` from the prelude names | check tests |
| `crates/ms-rt-abi`, `ms-std-*` | comments name codes | none |
| docs, wiki, guide | codes replace categories | `make docs` freshness |

## Alternatives

- Do nothing: user kinds stay impossible; the owner asked for this change.
- Keep the enum and add a `Custom(String)` case: two ways to say the same thing; every match needs a fallthrough.
- Integer codes: not readable in output, and collide across packages.

## Open questions

- Several parse and limit failures have no natural errno; they take `EBADMSG` and `EOVERFLOW`. Recommendation: keep, and let the message carry the specifics.
