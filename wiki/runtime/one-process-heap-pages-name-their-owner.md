[Wiki](../index.md) › [Runtime](index.md)

# One process heap: pages name their owner, an ended thread's heap is adopted

Decision (concurrency redesign, workstream A): all threads allocate small blocks from one reservation (`alloc.rs`). A page-table word per 64 KiB page holds class and owner; `free` and `realloc` treat every block alike and send a foreign block to the owner's remote-free stack. `release_heap` keeps pages and free lists for the next `claim_heap`, so a block outlives its thread and Rust code may keep blocks in process state. There is no heap cap short of 65536 live heaps.

Apply when: adding a thread that allocates, a process-wide cache of runtime blocks, or an address test on a pointer.
Evidence: `crates/ms-rt/src/alloc.rs` tests (`a_released_heap_is_adopted_with_its_blocks`, `more_than_256_heaps_exist_at_once`, `every_kind_of_block_frees_and_resizes_on_any_thread`); kernels and datastructures benches within noise of `5199601b`.
Verify: the unmapped base must be an address no pointer reaches (`UNMAPPED`); a zero base makes every low malloc address look like a heap block, and `fault::address_ordered_tables` crashed at start on a non-PIE binary.

The per-string scalar-count and position hint is gone (it was keyed by address and went stale when a string moved threads). Cost, measured: `s.get(i)` over a 200k-character ASCII string went from 6 ms to 554 ms (O(n) per call). A real fix stores an ASCII flag in the string tag, not a cache.

Non-ASCII text still pays O(index) per `get`, `scalar_at` and `slice` with nonnegative bounds (2026-11-07: `get(i)` over every index of a 100k-scalar mixed-script string, 23 s before walking from the front without counting the whole string, 7.9 s after). A cache keyed by address is ruled out for the reason above; a real fix needs scalar-index data stored in the string itself, and the string tag has no free bit.
