# Fallible close

## Summary

- `Closeable.close()` returns `Result[Unit, Error]`, so a failed flush or release is a value, not a fault.
- An implicit scope-end close never drops its error: it becomes the function's error, or the checker rejects the binding.
- Resource `clone()` returns `Result[Self, Error]`; plain-data `clone()` stays total and is the only `Clonable` one.
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
- Copying a resource (dup) can fail on descriptor limits or a closed handle; a total `clone()` can only fault or return a closed copy, both silent.
- Non-goals: user `defer`; making `clone()` fallible for plain data.

## Design

- `interface Closeable: var fn close() Result[Unit, Error]`. One error type keeps `T: Closeable` generic code uniform; implementations may return their own error through the `Error` boundary.
- Explicit `close()` follows the usual `Result` rules (`try`, `match`, `let _ =`) and consumes the binding, so no implicit close runs after it.
- Implicit close at scope end, by outcome:
  - Pending success or no error: a failed close becomes the function's error. The function must return a `Result` that accepts `Error`.
  - Pending error: the original error stays primary; the close error is recorded as a secondary diagnostic, as cleanup faults are today.
  - Fault or cancellation: unchanged (`cleanup-faults.md`); a close error is a secondary diagnostic.
- An implicit close is `try x.close()` at every scope exit, so the existing `try` rule applies: a function that cannot return `Error` is rejected with "this scope closes `file`; return a `Result` or call `close()` yourself".
- A close that cannot fail (locks, groups) declares `Result[Unit, Never]`; `try` on a `Never` error needs no `Result` in the enclosing function.
- When the body already failed and close also fails, the body's error is returned and the close error is only recorded as a diagnostic. This is the one path where an error is not returned.
- Example of an accepted program:

```manuscript
import FileHandle, open from "@std/fs.ms"

fn save(path: String, text: String) Result[Unit, Error]:
    var file = try open(path)
    try file.write(text)
    return ok(unit)
```

- Allocation failure (out of memory) is a fault everywhere in the language, including `clone()`, `push` and concatenation. Chinmay chose this on 2026-10-31; only I/O-backed operations return `Result`.
- Resources stay out of `Clonable`: lowering uses `Op::Copy` for internal copy-then-drop of temporaries, so a resource clone in the glue would run extra clones and drop the original without close (found in the #2029 thread).
- Clone: `Clonable.clone() Self` stays total and covers plain data only, so generic `T: Clonable` code never hides a syscall or a failure.
- A resource that can be copied declares an inherent `fn clone() Result[Self, Error]` (not a `Clonable` implementation). `FileHandle` and plain connections dup; the caller uses `try`.
- A resource has no `Clonable` impl, so generic or implicit copies (`List[FileHandle].clone()`, `T: Clonable`) stay compile errors, as today.
- TLS is a separate type with no `clone`; locks, guards and groups have none.

```manuscript
import FileHandle from "@std/fs.ms"

fn twice(file: FileHandle) Result[List[FileHandle], Error]:
    let copy = try file.clone()
    return ok([copy, file])
```

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/core.ms` and ~24 `Closeable` impls | New `close` signature, bodies return the native result | e2e per module |
| `crates/ms-check` cleanup facts and `close_method` | Match the new signature; reject unclosable-in-context bindings | `tests/ownership` reject cases |
| Lowering and MIR cleanup | Implicit close error feeds the function's return path | `crates/ms-mir/tests` |
| `FileHandle`/`Connection` in `stdlib/fs.ms`, `net.ms` | Add `clone() Result[Self, Error]` via dup | e2e + `reject/clonable-handle.ms` |
| Docs | `closeable.md`, `resource-release.md`, `exit-order.md`, `cleanup-faults.md` | `make repo-check` |

## Alternatives

- Do nothing: keeps silent loss; rejected.
- Total resource `clone()` that faults or returns a closed copy: silent; rejected.
- Fallible `Clonable.clone()` for every type: every plain-data copy needs `try`; rejected.
- Discard the implicit error (Rust `Drop`): incorrect programs; rejected by the requester.
- Fault on any close error: no recovery path and kills services; rejected.
- Keep `close()` as `Unit`, require `finish()`: relies on the author remembering; rejected.

## Open questions

- Should `main() Int` be allowed to propagate close errors as an exit status, or must it close explicitly?
- Overlap with PR #2029 (dup and TLS split): land it first; this proposal only changes `close`.
