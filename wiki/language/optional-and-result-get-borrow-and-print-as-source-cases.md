[Wiki](../index.md) › [Language](index.md)

# Optional and Result `get()` borrow alike; both print as source cases

Decision (Chinmay, 2026-11-09 audit): `opt.get()` and `result.get()` with no default borrow their receiver, so `var x = r.get()` is rejected for both ("reference into more than one place"). Before, a borrowed `Result.get()` silently deep-copied for a consumer, against the one-owner model. To take ownership of a payload from an owned local, use `get(none)` or `if let`; a stdlib site (`data/json.ms`) and a frozen net fixture relied on the hole and were rewritten.

Text conversion (`print`, interpolation, `to_string`, test `repr`) shows `some(v)`, `none`, `ok(v)`, `error(e)`, the source spellings, not `Optional.some(v)`. Other enums keep `Type.Case`.

Check: `crates/ms-check/tests/ownership/reject/var_borrow_of_result_get.ms`, `tests/e2e/testdata/accept/to-string.ms`.
