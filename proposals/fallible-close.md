# Fallible close

## Summary

- `Closeable.close()` returns `Result[Unit, Error]`, so a failed flush or release is a value, not a fault.
- An implicit scope-end close never drops its error: it becomes the function's error, or the checker rejects the binding.
- `clone()` stays total (`fn clone() Self`); only types whose copy cannot fail are `Clonable`.
- Decision requested: approve the rules below before any implementation.

## Status

Proposal, 2026-10-31, checked against `ea4dfeab`.

- Chinmay: "i feel a bit bad that close and clone cannot return errors nicely".
- Chinmay: "that'll create incorrect programs" (about ignoring an implicit close error).
- Chinmay: "may be we don't make anything go silently?"
- Chinmay on clone: "only for clonable objects" (a type is `Clonable` only when its clone always works).

## Problem

- `Closeable.close()` returns `Unit` (`stdlib/core.ms`). An unexpected release failure is a cleanup fault; expected failures need a separate `flush()`/`commit()` the caller must remember (`documentation/core-language/cleanup/closeable.md`).
- Forgetting that method loses data silently: the scope closes the file and the failure is invisible or kills the program.
- Non-goals: user `defer`; changing `clone()`'s signature; making locks or groups fallible.

## Design

- `interface Closeable: var fn close() Result[Unit, Error]`. One error type keeps `T: Closeable` generic code uniform; implementations may return their own error through the `Error` boundary.
- Explicit `close()` follows the usual `Result` rules (`try`, `match`, `let _ =`) and consumes the binding, so no implicit close runs after it.
- Implicit close at scope end, by outcome:
  - Pending success or no error: a failed close becomes the function's error. The function must return a `Result` that accepts `Error`.
  - Pending error: the original error stays primary; the close error is recorded as a secondary diagnostic, as cleanup faults are today.
  - Fault or cancellation: unchanged (`cleanup-faults.md`); a close error is a secondary diagnostic.
- Checker rule: a binding with a fallible close that is not explicitly closed, in a function that cannot return `Error`, is rejected with "call `close()` and handle the result". Example of an accepted program:

```manuscript
import FileHandle, open from "@std/fs.ms"

fn save(path: String, text: String) Result[Unit, Error]:
    var file = try open(path)
    try file.write(text)
    return ok(unit)
```

- Clone: `clone()` is not fallible. `FileHandle` and plain connections are `Clonable` through dup; running out of descriptors faults like running out of memory. TLS is a separate non-`Clonable` type. Locks, guards and groups are not `Clonable`.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms` and ~24 `Closeable` impls | New `close` signature, bodies return the native result | e2e per module |
| `crates/ms-check` cleanup facts and `close_method` | Match the new signature; reject unclosable-in-context bindings | `tests/ownership` reject cases |
| Lowering and MIR cleanup | Implicit close error feeds the function's return path | `crates/ms-mir/tests` |
| Docs | `closeable.md`, `resource-release.md`, `exit-order.md`, `cleanup-faults.md` | `make repo-check` |

## Alternatives

- Do nothing: keeps silent loss; rejected.
- Discard the implicit error (Rust `Drop`): incorrect programs; rejected by the requester.
- Fault on any close error: no recovery path and kills services; rejected.
- Keep `close()` as `Unit`, require `finish()`: relies on the author remembering; rejected.

## Open questions

- Should a close that cannot fail (locks, groups) keep `Unit`, via a second interface or `Result[Unit, Never]`?
- Should `main() Int` be allowed to propagate close errors as an exit status, or must it close explicitly?
- Overlap with PR #2029 (dup and TLS split): land it first; this proposal only changes `close`.
