[Wiki](../index.md) › [Compiler and build](index.md)

# Unwind leaves slot values to an active scope close

Verified (#2376): after inlining, a mutable method such as `Wrapper.read` becomes `take` from a local slot, a borrowing call, then `put`. The slot's scope close is registered as `close_drop_slot`, which closes and then drops what the slot holds. The unwind pass also registered a drop for the taken value. Cleanups run last-in first-out, so that drop freed the receiver before the older close used it, and two promise faults in a row corrupted the heap.

The fix is narrow. A `take` from a local slot whose scope close is registered and not yet discarded does not own its result when every use only borrows it or puts it back into that slot (`covered_slot_takes` in `unwind.rs`). Coverage is a must-analysis over the control-flow graph that ends at the matching `msrt_cleanup_discard`; after it the value is owned again and gets its own unwind drop. A taken value that is consumed, mutated by `rec.set`, moved in parts or returned keeps the old behavior.

The 1000-line #2281 pass was reverted (#2350) because the faulting fixtures lost frames on Windows and macOS; do not restore it, `SharedGuard` or `TaskGroup`.

Apply when: changing the unwind pass, inlining of mutable methods, or slot-held cleanup entries.
Evidence: [lifecycle fixture](../../tests/e2e/testdata/accept/promise-fault-scope-close-unwind.ms), [MIR controls](../../crates/ms-mir/tests/unwind.rs).
Verify: run the fixture in Debug under valgrind or a counting runtime, and dispatch the full platform matrix.
