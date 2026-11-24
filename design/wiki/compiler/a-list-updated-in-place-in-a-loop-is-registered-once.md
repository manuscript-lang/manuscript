[Wiki](../index.md) › [Compiler and build](index.md)

# A list updated in place in a loop is registered once

Verified (2026-11-14, x86-64, callgrind): inside a promise task, a loop that did `hist[i] = hist[i] + 1` pushed and discarded a cleanup record for the list around every faulting instruction of every iteration, because MIR threads the list through a header block parameter (`list.set` consumes it and returns the next value). `hoist_loops` only hoisted values live before the header. The `workers` chunk loop ran 185 ms in a task against 113 ms called directly (3.51G against 1.21G instructions, one thread).

`stable_params` in `crates/ms-mir/src/unwind.rs` now recognizes a header parameter whose latch values are a chain of `list.set`s starting at it, with no other consumer. `list.set` returns the same pointer, length and capacity, so one record from the pre-header names the live list for the whole chain. Lists whose elements need a drop are excluded: `set` drops the old element before the store, so an unwind between the two would drop it twice. A bounds fault inside the loop now drops the list instead of leaking it.

Apply when: adding another in-place list op (it joins the chain only if it returns the same triple), or extending the rule to elements that need a drop (the old element would have to be handled first). Verify: `registers_a_list_updated_in_place_across_a_loop_once` in `crates/ms-mir/tests/unwind.rs`; fixture `promise-list-update-loop-unwind`.
