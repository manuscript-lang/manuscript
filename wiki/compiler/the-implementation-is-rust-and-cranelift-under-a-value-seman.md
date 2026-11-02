[Wiki](../index.md) › [Compiler and build](index.md)

# The implementation is Rust and Cranelift under a value-semantics model

Decision: the compiler, runtime, standard library, and tools use Rust with Cranelift under a value-semantics memory model. Values have one owner and are dropped deterministically; `var` marks mutation, plain values copy, and other values move at their last use into consuming positions. The current contract is in [the design contract](../../crates/DESIGN.md) and [ownership notes](../../crates/ms-check/OWNERSHIP.md).

Apply when: changing ownership, borrowing, drop elaboration, or argument passing in the checker, MIR, or runtime.
Evidence: [local copy elimination](../../crates/ms-mir/src/opt/copyelim.rs), [record-copy lifetime regressions](../../crates/ms-mir/tests/opt_copyelim.rs), [native payload lifetime checks](../../crates/ms-clif/tests/native.rs).
Evidence: [ownership corpus](../../crates/ms-check/tests/ownership.rs), [ownership notes](../../crates/ms-check/OWNERSHIP.md).
Evidence: [closure alias regressions](../../crates/ms-cli/tests/closure_aliases.rs), [bound alias regressions](../../crates/ms-cli/tests/bound_aliases.rs).
Verify: read-only record iteration loses its deep copy; dropping the source container or replacing its parent field keeps the independent copy.
Verify: `cargo nextest run -p ms-check`, including the accept and reject ownership fixtures; add the rejected aliasing case before relaxing a rule.
Verify: native Debug and Release runs cover indexed/keyed paths, nested callbacks, source/native methods, owned results, and rejected escape/reentry.
