[Wiki](../index.md) › [Benchmarks and performance](index.md)

# Generic list search and the priority queue lose on instructions per element

Verified (2026-11-14, callgrind, release `ms`): `List[String].index_of` (20k searches over 2,000 strings) is 2.3x Rust's `position`: 54 instructions per element against about 17. `List.index_of` and `contains` are generic `.ms` loops (`stdlib/collections/collections.ms`); each element runs the inline word decision of `eq_words` (about 25 instructions of selects) and, for two strings of one length with different blocks, a call to `msrt_string_eq` (about 27 more). `contains` over `Int` is not a gap: LLVM vectorizes the loop and it is memory bound (equal to Rust on repeat runs; the 1.58x in the round-2 probe was noise).

Tried, each under 10% and dropped: an early branch on the length-differs test before the rest of the word decision in both backends (1,078M to 958M instructions, wall 42 to 39 ms); a runtime string loop in `msrt_list_index_of` (no change, the `.ms` loop is what runs). A real fix is an inline compare of the first and last eight bytes for two non-inline strings of 8 to 16 bytes in both backends (LLVM `eq_words` and Cranelift `string_eq_call`), so equal-length different-block pairs skip the call.

`PriorityQueue` (`stdlib/collections/queue.ms`) is 1.5x Rust's `BinaryHeap` and 2x its instructions (273M against 135M for 500k enqueue and dequeue): a third is `heap.swap` (about 9 instructions per 16-byte entry; Rust moves a hole, one store per level) and another quarter is the two entry loads per comparison. Comparing in place instead of binding both entries saved 3%. Entries carry a sequence number for FIFO ties, which `BinaryHeap` does not pay for. A hole-based sift needs a move primitive for owned elements (the list has `swap` and `pop` only), so it is a language-library decision, not a rewrite of the loop.

Apply when: someone proposes a micro-fix for `index_of`, `contains` or `PriorityQueue`: start from these counts.
