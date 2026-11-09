[Wiki](../index.md) › [Testing and conformance](index.md)

# The close matrix generates every resource shape and construct

Verified (2026-11-09): the resource matrix covers standard operations, but the same "close once" duty is also implemented per language construct in `crates/ms-lower` (`close.rs`, `call.rs`, `stmt.rs`, `matching.rs`, `closure.rs`; about 110 close/drop helper call sites), so a construct nobody wrote a fixture for can still leak or double close. `make close-matrix` (`tools/close-matrix.ms`, a gate step in CI) generates each (shape × construct): shapes are a bare resource, `Optional`, `List`, `Map`, a record, an enum, a `Result` and a `List` of `Optional`; constructs are scope end, early return, `try` error, loop exits, reassignment, by-value arguments (direct, method, method value, function value, interface, generic, later `try`), returned owners, closures that borrow or escape, promise capture, result and cancellation, explicit close, `if let`, `match` and destructuring. The oracle is the resource matrix's: exit normally, and every `made-N` is matched by exactly one `closed-N` (the test resource's `close` is idempotent, so an explicit close followed by the scope end counts once).

First run (792 runs, Debug and Release) found two leaks, both in staging an argument that changes type on the way into a call:

- A temporary converted to an `Optional` parameter (`take(Door("x"), try fails())`) was held as the generated optional, which has no checker type, so `part_closer_mir` found no closer and a later argument's `try` error leaked it. `args` now resolves the payload closer before the conversion and composes `optional_resource_closer` around it, as function-value calls already do.
- A temporary passed to a `Closeable` interface parameter (`look(Door("x"))`) became an owned interface value with no checker type, and was dropped without its close. `part_closer_mir` reads the closer from the interface's vtable entry first.

Both share the cause that the wiki already records for function-value calls: a MIR type made by lowering (optional shell, interface box) has no checker-type entry, so any closer lookup keyed by checker type silently returns "not a resource". Resolve the closer from the payload before the conversion, or from the MIR kind, never from `source_tys` of the converted value.

Design note (not implemented): `close()` is documented as idempotent, and an explicit close followed by the scope-end close is intended, so use-after-close is a runtime result (`EBADF` for handles), not a compile error. Rejecting a use after an explicit `close()` would change that contract and needs the owner's decision.

Apply when: adding a construct that moves, drops or closes a value, or a lowering step that changes a value's MIR type before a call.
Evidence: [tools/close-matrix.ms](../../tools/close-matrix.ms), fixtures `close-optional-parameter-later-try.ms` and `close-interface-parameter-temporary.ms` under `tests/conformance/fixtures/e2e/stdlib/`.
Verify: `make close-matrix` ends with `0 failing`; a new construct is a row in `constructs()`.
