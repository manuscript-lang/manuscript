[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Generic list search and the priority queue lose on instructions per element

Verified (2026-11-14, callgrind, release `ms`): `List[String].index_of` (20k searches over 2,000 strings) was 2.3x Rust's `position`: 54 instructions per element against about 17. `List.index_of` and `contains` are generic `.ms` loops (`stdlib/collections/collections.ms`); before the fix each element ran the inline word decision (about 25 instructions of selects) and, for two strings of one length with different blocks, a call to `msrt_string_eq` (about 27 more). `contains` over `Int` is not a gap: LLVM vectorizes the loop and it is memory bound (equal to Rust on repeat runs; the 1.58x in the round-2 probe was noise).

Fixed in part (2026-11-14): the decision was a branchless chain of selects run for every element. Branching on the one xor that separates most pairs, then on equal tagged words, in both backends took 1,078M to 793M instructions and the search loop 47 to 35 ms (`bench/perf/index-of`). An early length branch alone gave only 958M. The rest is the `msrt_string_eq` call for same-length pairs with different blocks; an inline compare of the first and last eight bytes of two non-inline strings gained 4% on top of the old chain, so measure it against the branchy code before building it. A runtime string loop in `msrt_list_index_of` changed nothing: the `.ms` loop is what runs.

`PriorityQueue` (`stdlib/collections/queue.ms`) is 1.5x Rust's `BinaryHeap` and 2x its instructions (273M against 135M for 500k enqueue and dequeue): a third is `heap.swap` (about 9 instructions per 16-byte entry; Rust moves a hole, one store per level) and another quarter is the two entry loads per comparison. Comparing in place instead of binding both entries saved 3%. Entries carry a sequence number for FIFO ties, which `BinaryHeap` does not pay for. A hole-based sift needs a move primitive for owned elements (the list has `swap` and `pop` only), so it is a language-library decision, not a rewrite of the loop.

Apply when: someone proposes a micro-fix for `index_of`, `contains` or `PriorityQueue`: start from these counts.
