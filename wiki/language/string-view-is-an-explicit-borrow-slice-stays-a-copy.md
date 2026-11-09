[Wiki](../index.md) › [Language](index.md)

# String.view is an explicit borrow; slice stays a copy

Decision (Chinmay, 2026-11-09): O(1) substrings are explicit borrows checked by the borrow checker, not compiler elision. `String.view(start, end)` mirrors `Bytes.view`: scalar bounds like `slice`, a fault outside them, the receiver frozen while the view lives, storing or returning it needs `.clone()`. `slice` is unchanged (owned copy, `ERANGE` error), because making it a borrow rejects every program that stores its result.

Verified: a stored `Bytes.view` (`list.append(b.view(0, 2))`) passed `ms check` and then failed in lowering with "implicit copies of a borrow"; `calls.rs` now reports it as a type error for `Bytes` and `String` views of a place. Native borrows such as `Map.get(k).get()` are still copied when stored, which is a separate gap.

Apply when: adding a borrowed accessor to a native type (add it to `native_borrow_receiver`, the `returned_bytes_view` check, lowering, and an e2e plus reject fixture).
Evidence: `proposals/string-view.md`, `tests/e2e/testdata/{stdlib/string-view.ms,reject/*string-view*.ms}`.
