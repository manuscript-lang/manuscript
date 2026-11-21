[Wiki](../index.md) › [Language](index.md)

# String.view is an explicit borrow; slice stays a copy

Decision (Chinmay, 2026-11-09): O(1) substrings are explicit borrows checked by the borrow checker, not compiler elision. `String.view(start, end)` mirrors `Bytes.view`: scalar bounds like `slice`, a fault outside them, the receiver frozen while the view lives, storing or returning it needs `.clone()`. `slice` is unchanged (owned copy, `ERANGE` error), because making it a borrow rejects every program that stores its result.

Verified: a stored `Bytes.view` (`list.append(b.view(0, 2))`) passed `ms check` and then failed in lowering with "implicit copies of a borrow"; `calls.rs` now reports it as a type error for `Bytes` and `String` views of a place. Native borrows such as `Map.get(k).get()` are still copied when stored, which is a separate gap.

Apply when: adding a borrowed accessor to a native type (add it to `native_borrow_receiver`, the `returned_bytes_view` check, lowering, and an e2e plus reject fixture).
Evidence: `proposals/string-view.md`, `tests/conformance/fixtures/e2e/{src/stdlib/string-view.ms,reject/*string-view*.ms}`.

Short views stay copies (tried 2026-11-15, #4084): a `String` of 15 bytes or less is always inline, and compiled equality (`string_eq_call`), `starts_with`, `clone` and the map probe read that as an invariant (strings of different kinds are equal only at one length, an inline string's words are its bytes). Making `msrt_string_view` return a borrowed `StrVal::view` for a short range, even with the argument slot pinned (`// ms: borrows`), made `"hé" == part` and `part.starts_with("h")` false in a `test` block. `view_of` therefore copies a short piece; only `Bytes`, which has no inline form, borrows short text (`String.view_bytes`).

