[Wiki](../index.md) › [Testing and conformance](index.md)

# The close matrix generates every resource shape and construct

Verified (2026-11-09): the resource matrix covers standard operations, but the same "close once" duty is also implemented per language construct in `crates/ms-lower` (`close.rs`, `call.rs`, `stmt.rs`, `matching.rs`, `closure.rs`; about 110 close/drop helper call sites), so a construct nobody wrote a fixture for can still leak or double close. `make close-matrix` (`tools/close-matrix.ms`, a gate step in CI) generates each (shape × construct): shapes are a bare resource, `Optional`, `List`, `Map`, a record, an enum, a `Result` and a `List` of `Optional`; constructs are scope end, early return, `try` error, loop exits, reassignment, by-value arguments (direct, method, method value, function value, interface, generic, later `try`), returned owners, closures that borrow or escape, promise capture, result and cancellation, explicit close, `if v := x`, `match` and destructuring. The oracle is the resource matrix's: exit normally, and every `made-N` is matched by exactly one `closed-N` (the test resource's `close` is idempotent, so an explicit close followed by the scope end counts once).

First run (792 runs, Debug and Release) found two leaks, both in staging an argument that changes type on the way into a call:

- A temporary converted to an `Optional` parameter (`take(Door("x"), try fails())`) was held as the optional lowering built, and `part_closer_mir` found no closer, so a later argument's `try` error leaked it.
- A temporary passed to a `Closeable` interface parameter (`look(Door("x"))`) became an owned interface value that was dropped without its close.

Root cause: `source_tys` (MIR type to checker type, read by every closer lookup) is filled when a checker type is lowered. The optional built for an argument conversion exists before the callee's `T?` parameter is lowered, so its entry is missing (order-dependent), and interface types are never entered. A missing entry reads as "not a resource" and nothing closes. `part_closer_mir` now takes the closer from the MIR kind when there is no entry: an interface from its vtable entry, an optional from its payload's closer (`generated_closer`). A record, alternative, list or object type with no entry is a debug assertion, so a lowering-made type that holds resources fails loudly instead of leaking. Never decide "not a resource" from a missing `source_tys` entry.

Design note (not implemented): `close()` is documented as idempotent, and an explicit close followed by the scope-end close is intended, so use-after-close is a runtime result (`EBADF` for handles), not a compile error. Rejecting a use after an explicit `close()` would change that contract and needs the owner's decision.

Apply when: adding a construct that moves, drops or closes a value, or a lowering step that changes a value's MIR type before a call.
Evidence: [tools/close-matrix.ms](../../tools/close-matrix.ms), fixtures `close-optional-parameter-later-try.ms` and `close-interface-parameter-temporary.ms` under `tests/conformance/fixtures/e2e/stdlib/`.
Verify: `make close-matrix` ends with `0 failing`; a new construct is a row in `constructs()`.
