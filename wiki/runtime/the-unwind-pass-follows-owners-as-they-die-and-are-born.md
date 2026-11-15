[Wiki](../index.md) › [Runtime](index.md)

# The unwind pass follows owners as they die and are born

Verified 2026-11-15 (#3979): in a program that starts tasks or catches faults (every `ms test` run), `crates/ms-mir/src/unwind.rs` registers a cleanup for each owner live across a call that can park or fault. A window used to end whenever an owner died, and the next call registered every live owner again, so N long-lived owners with a temporary around each call cost N² `cleanup.push` instructions and N² 24-byte stack slots. A `test` with 150 list locals captured by closures had a 569 KB frame and died with `stack overflow` on the 512 KiB task slot (Release segfaulted); 200 pairs were 438K Cranelift lines against 6K in `main`. Now a window keeps its registrations and, when the live set changes, discards the first dead entry (a discard pops it and everything newer) and registers again only the owners above it plus the new ones; 200 pairs lower to about 37K lines in total.

Still quadratic across blocks: a window never crosses a block boundary, so a body that branches between statements (an `if` after each of 100 statements with a captured list: 238K Cranelift lines, stack overflow) re-registers the live owners per block. Continuing a window across blocks must keep the stack state exact: a value registered twice is dropped twice on unwind, a loop-exit `discard` from `hoist_loops` pops every entry newer than its handle, and a join needs the common prefix of its predecessors with edge discards for the excess (#3979).

Rules that keep it sound: a window closes at a scope open or close (`CleanupPush`, `CleanupRun`), at a loop-exit `discard`, and inside a moved-out hole; an exit instruction with no live owners still pops what the window holds, so a consumed value is never left registered across a call that can fault.

Apply when: changing `analyze` or the window materializer in `unwind.rs`, or adding an instruction that consumes an owner.
Evidence: [`unwind.rs`](../../crates/ms-mir/src/unwind.rs), test `registrations_grow_linearly_with_the_owners_a_function_holds` in `crates/ms-mir/tests/unwind.rs`.
Verify: `cargo test -p ms-mir --test it unwind::`; `ms test` on a body of 200 `xs: List[Int] := [...]` locals each captured by a closure passed to a function passes in Debug and Release.
