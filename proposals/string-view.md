# String.view: an explicit borrowed range of a String

## Summary

- Problem: `String.slice` always copies, so read-only parsing that walks a string (`rest.slice(at + 1, n)`, then `starts_with` or `index_of`) allocates and copies the remainder per step. `trim` and `split` avoid the copy only through a lowering elision the checker does not know about.
- Change: add `String.view(start, end) String`, the `String` counterpart of `Bytes.view`: a real borrow of the receiver, with the checker's usual rules. `slice` is unchanged and keeps returning an owned copy and an `ERANGE` error.
- Decision requested: none; this implements the direction below.

## Status

Implemented 2026-11-09 on `f6304403`. Direction (Chinmay): "let's do real borrows, no compiler level magic for these", after "we added a new method" (`Bytes.view`, wiki `a-bytes-view-is-a-cap-zero-borrow-never-freed.md`).

## Problem

Measured (micro, 4000-byte text, 3900 iterations, `let tail = text.slice(i, n).get()` against `let tail = text.view(i, n)`, then `tail.starts_with("ab")`): 400 to 530 us against 79 to 190 us. Programs in `bench/agent/challenges` (c03, c09) copy a remainder per field.

Making `slice` itself return a borrow would reject every program that stores its result (`parts.append(rest.slice(..).get())`, `rest = rest.slice(..)`), about 400 call sites in stdlib, tests and bench, and would turn `ERANGE` handling into faults. A separate method keeps both, as `Bytes` does.

## Design

```manuscript
fn count_a(text: String) Int:
    let head = text.view(0, 4)      // borrows `text`, nothing allocated
    var n = 0
    for c in head.scalar_values():
        if c == 97:
            n += 1
    return n
```

- Bounds are scalar positions with the bounds of `slice` (negative counts from the end); a bound outside `0 <= start <= end <= scalar_length()` raises a fault, like `Bytes.view`.
- The checker lists `view` among the native reads that return a borrow (`native_borrow_receiver`): the receiver cannot change while the view is used (`cannot reassign text while word borrows it`).
- Returning a view of a local or parameter is rejected, as for `Bytes.view`; storing a view of a place (a collection append, a field) is rejected with the `.clone()` remedy. A view of a temporary is copied out before the temporary drops.
- Runtime `msrt_string_view` writes a `StrVal` that points into the receiver (`view_of`); text of 16 bytes or less is inline either way, so nothing is shared.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `stdlib/intrinsics.ms` | `String.view` declaration | `tests/e2e/testdata/stdlib/string-view.ms` |
| `crates/ms-rt/src/string.rs`, `rt_symbols.txt` | `msrt_string_view`, `scalar_range` | same, plus an out-of-range fault run |
| `crates/ms-check/src/ownership/walk/{returns,calls}.rs` | `view` borrows for `String`; storing a view of a place is an error (also fixes a lowering crash for a stored `Bytes.view`) | `tests/e2e/testdata/reject/{return-string-view,string-view-source-changed,string-view-stored}.ms` |
| `crates/ms-lower/src/native/method.rs` | `(Str, "view")` like `(Bytes, "view")` | stdlib test |
| docs, goldens | `text-and-bytes.md`; member-count goldens 58 to 59 | `make docs-check`, golden tests |

## Alternatives

- Make `slice` return a borrow: large migration, loses the `ERANGE` result; rejected above.
- Extend the `trim_view` lowering elision to `slice`: no language change, but it only helps results that are provably read in place, and the user rejected compiler-level magic for these.
- Do nothing: the copy stays in every cursor-style parser.

## Open questions

- Whether `trim` and `split` should also move to explicit borrows (they keep the lowering elision today).
