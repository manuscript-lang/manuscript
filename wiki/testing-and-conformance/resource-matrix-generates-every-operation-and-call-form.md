[Wiki](../index.md) › [Testing and conformance](index.md)

# The resource matrix generates every operation, call form and argument form

Verified (2026-11-08): after the MIR drop verifier landed, ~15 more ownership bugs (#3049, #3053, #3075, #3078, #3086 and others) were still one standard operation in one call form with one resource shape, each found by hand and fixed with one more fixture. The verifier proves the drops lowering chose; it does not know a bound `list.remove` should close the entry, or that `Result.get` passes a payload through. `make resource-matrix` (`tools/resource-matrix.ms`, a gate step in CI) generates each (operation × direct or method-value call × temporary or named argument) and runs the ones `ms check` accepts in Debug and Release against one oracle: `mk` prints `made-N`, `close` prints `closed-N`, and they must match, with a normal exit. The first run found a bound `Result.get` closing its payload twice and a bound `List.remove` never closing its entry.

Passthrough is read from the declaration, not a name list: `wrapper_passthrough` takes the wrapper type parameter (`T`, `E`) the declared result mentions, for direct calls and method values alike, so a new `Optional` or `Result` operation cannot be left off (it skips contract operations such as `clone`, which make a new value). A direct `Result.get()` and `err()` are now passthroughs like `Optional.get`; `result-argument-inference.ms` is unaffected. `effects::discards_entries` is the one list of discarding mutators, shared by the checker and lowering.

Coverage (2026-11-08): the tool also reads `ms search_symbol prelude.<Type> --json` for List, Map, Set, Optional and Result and fails when an operation that changes the receiver or mentions a type parameter outside a callback has neither a row nor a reason in `exempt()`. A new stdlib operation therefore cannot ship unclassified. Rows added for it found a bound `Map.get` that double-closed its entry (a method value now requires a clonable element) and `List.get(i, default)` over resources, which copied an element out of the list (now rejected: a collection cannot hand one over). Sets are an open gap: the matrix has no Hashable resource.

Apply when: adding or changing a standard operation that takes, returns or discards a `T`, or a call form (method value, interface, function value).
Evidence: [tools/resource-matrix.ms](../../tools/resource-matrix.ms), [wrapper_passthrough tests](../../crates/ms-check/tests/wrapper_passthrough.rs).
Verify: add a row to `operations()` and run `make resource-matrix`; a combination that must not be accepted is rejected by the checker, never skipped in the tool.

Native discard classifications apply only to native collection methods, not arbitrary source methods named `remove`, `clear`, `set`, `add`, or `splice`. A generic source receiver may hold a resource while such a method only updates a counter (#3106); retain a same-name acceptance control alongside native rejection cases.
