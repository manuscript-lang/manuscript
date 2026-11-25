[Wiki](../index.md) › [Language](index.md)

# Optional and Result `get()` borrow alike; both print as source cases

Decision (Chinmay, 2026-11-09 audit): `opt.get()` and `result.get()` with no default borrow their receiver, so `var x = r.get()` is rejected for both ("it borrows its receiver; end the initializer with `.clone()`"). Before, a borrowed `Result.get()` silently deep-copied for a consumer, against the one-owner model. `get()` on the last use of an owned local moves the payload out (`if f := r.get() { out.append(f) }`), as does `r?` (#3322). A borrowed receiver stays a borrow. Otherwise use `get(none)` or `if v := x`; a stdlib site (`data/json.ms`) and a frozen net fixture relied on the hole and were rewritten.

Lesson (hardening 2026-11-16): `get_or(default)` hands back the payload too, so on a receiver that borrows (`xs.slice(0, 2).get([])`, or a local bound to a slice) the result keeps that borrow; before, `ys := xs.slice(0, 2).get([])` followed by `xs.append(..)` left `ys` dangling and printed freed memory. An owned receiver still copies (`final.failure.get(message)`). Fixture: `e2e/reject/slice-get-default-borrows-list`.

Text conversion (`print`, interpolation, `to_string`, test `repr`) shows `some(v)`, `none`, `ok(v)`, `error(e)`, the source spellings, not `Optional.some(v)`. Other enums keep `Type.Case`.

Check: `ms run tools/conform.ms` (CI's conformance job runs it; a narrower runner once missed five e2e fixtures), the ownership checks under `tests/checks/ownership-counts/`, `tests/conformance/fixtures/e2e/accept/to-string.ms`.
