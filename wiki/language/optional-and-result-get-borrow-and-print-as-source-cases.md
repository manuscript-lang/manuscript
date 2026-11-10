[Wiki](../index.md) › [Language](index.md)

# Optional and Result `get()` borrow alike; both print as source cases

Decision (Chinmay, 2026-11-09 audit): `opt.get()` and `result.get()` with no default borrow their receiver, so `var x = r.get()` is rejected for both ("reference into more than one place"). Before, a borrowed `Result.get()` silently deep-copied for a consumer, against the one-owner model. `get()` on the last use of an owned local moves the payload out (`if f := r.get(): out.append(f)`), as does `try r` (#3322). A borrowed receiver stays a borrow. Otherwise use `get(none)` or `if v := x`; a stdlib site (`data/json.ms`) and a frozen net fixture relied on the hole and were rewritten.

Text conversion (`print`, interpolation, `to_string`, test `repr`) shows `some(v)`, `none`, `ok(v)`, `error(e)`, the source spellings, not `Optional.some(v)`. Other enums keep `Type.Case`.

Check: `ms run tools/e2e.ms` (CI's conformance job runs it; `ms-conform` alone missed five e2e fixtures), `crates/ms-check/tests/ownership/accept/try_owned_result_local_moves_payload.ms`, `crates/ms-check/tests/ownership/reject/var_borrow_of_result_get.ms`, `tests/e2e/testdata/accept/to-string.ms`.
