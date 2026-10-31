[Wiki](../index.md) › [Compiler and build](index.md)

# The implementation is Rust and Cranelift under a value-semantics model

Decision: the compiler, runtime, standard library, and tools use Rust with Cranelift under a value-semantics memory model. Values have one owner and are dropped deterministically; `var` marks mutation, plain values copy, and other values move at their last use into consuming positions. The current contract is in [the design contract](../../crates/DESIGN.md) and [ownership notes](../../crates/ms-check/OWNERSHIP.md).

Verified: exclusivity must be enforced per borrowing construct and checked with both rejection cases and native execution. Well-formed programs and leak-free happy paths alone do not establish memory safety.

Verified: a local aggregate copy used only for reading can borrow its original when the source stays alive. An intervening write or reference release can invalidate a projection even when it never directly consumes that projection: replacing a parent field may free its old payload. The local copy pass permits string-length caching and additional copies, but otherwise rejects writes and releases during the borrowed span.
Evidence: [local copy elimination](../../crates/ms-mir/src/opt/copyelim.rs), [record-copy lifetime regressions](../../crates/ms-mir/tests/opt_copyelim.rs), [native payload lifetime checks](../../crates/ms-clif/tests/native.rs).
Verify: read-only record iteration loses its deep copy; dropping the source container or replacing its parent field keeps the independent copy.

Apply when: changing ownership, borrowing, drop elaboration, or argument passing in the checker, MIR, or runtime.
Evidence: [ownership corpus](../../crates/ms-check/tests/ownership.rs), [ownership notes](../../crates/ms-check/OWNERSHIP.md).
Verify: `cargo nextest run -p ms-check`, including the accept and reject ownership fixtures; add the rejected aliasing case before relaxing a rule.

Verified: a closure or method value that changes a mutable alias must retain the owner's storage and the already evaluated path operands. Capturing the leaf copies it; retaining parent-function SSA identifiers is invalid in the child function. A borrowed slot still permits source-call writeback, but the child must not drop its owner. Bound-method writeback must update the current root after the call so a callback's changes to disjoint fields survive.
Evidence: [closure alias regressions](../../crates/ms-cli/tests/closure_aliases.rs), [bound alias regressions](../../crates/ms-cli/tests/bound_aliases.rs).
Verify: native Debug and Release runs cover indexed/keyed paths, nested callbacks, source/native methods, owned results, and rejected escape/reentry.

---
Topics: [Ownership and value semantics](../topics/ownership-and-values.md) · [Testing](../topics/testing.md)
