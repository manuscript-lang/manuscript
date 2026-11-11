[Wiki](../index.md) › [Compiler and build](index.md)

# Unwind leaves slot values to an active scope close

Verified (#2376): after inlining, a mutable method such as `Wrapper.read` becomes `take` from a local slot, a borrowing call, then `put`. The slot's scope close is registered as `close_drop_slot`, which closes and then drops what the slot holds. The unwind pass also registered a drop for the taken value. Cleanups run last-in first-out, so that drop freed the receiver before the older close used it, and two promise faults in a row corrupted the heap.

The fix is narrow. A `take` from a local slot whose scope close is registered and not yet discarded does not own its result when every use only borrows it or puts it back into that slot (`covered_slot_takes` in `unwind.rs`). Coverage is a must-analysis over the control-flow graph that ends at the matching `msrt_cleanup_discard`; after it the value is owned again and gets its own unwind drop. A taken value that is consumed, mutated by `rec.set`, moved in parts or returned keeps the old behavior.

The 1000-line #2281 pass was reverted (#2350) because the faulting fixtures lost frames on Windows and macOS; do not restore it, `SharedGuard` or `TaskGroup`.

A slot passed to a `call.ind` is covered when every closure of that arity only borrows the pointer at that position (`closures_borrow`). The compiler-built `serve.stream` thunk keeps the exchange in such a slot, so before this a faulting HTTP handler leaked one 8-byte block per fault (fixture `http-fault-handler-frees-exchange-view`).

A slot pointer a closure captures by reference (`closure.cap` of type `ptr`) is the enclosing function's slot, like a parameter: a `take` from it is the owner's, not the closure's (#3040). Before, a `promise(fn: input.next())` over a borrowed `var input` dropped the stream's source when its limit cancelled the read, and the caller's later `close` crashed. Fixtures: `net.ms` and `http-websocket.ms` (`a read cancelled by its timeout leaves the stream closable`).

A field moved out of a value taken from the caller's slot and refilled (`self.pending.pop()` before a park) yields the same value again, so the `rec.fill` / `list.fill` result stays the caller's (#3130). Before, cancelling `fs.watch` mid-read dropped the watcher twice (BTreeMap panic, or a segfault in the allocator later). Fixtures: `fs-watch-cancel.ms`, `leaves_a_record_refilled_after_a_field_move_to_the_caller` in `crates/ms-mir/tests/unwind.rs`.

Apply when: changing the unwind pass, inlining of mutable methods, or slot-held cleanup entries.
Evidence: [lifecycle fixture](../../tests/conformance/fixtures/e2e/accept/promise-fault-scope-close-unwind.ms), [MIR controls](../../crates/ms-mir/tests/unwind.rs).
Verify: run the fixture in Debug under valgrind or a counting runtime, and dispatch the full platform matrix.
