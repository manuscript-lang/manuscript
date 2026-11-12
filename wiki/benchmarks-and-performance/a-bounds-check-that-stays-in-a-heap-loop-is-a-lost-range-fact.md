[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A bounds check that stays in a heap loop is a lost range fact

Verified (2026-11-12): a hole-based binary heap in Manuscript executed 56.0M instructions against Rust's `BinaryHeap` at 47.1M for 100k enqueues and dequeues; the gap was four bounds checks per sift level, not code quality. The range pass lost the facts for four reasons: a block parameter joining lists of different origins made every derived list `Mixed`; `shl` was not modeled (`2 * at + 1` became top); widening went straight to `i64::MAX`, where that step wraps and drops the other bound in a cycle narrowing cannot fix; and a relation to `len - 2` was pruned because nothing reads `len - 2` later. After the fix the heap is 46.0M, under Rust.

Apply when: an equivalent program emits more instructions than Rust and the extra ones are compares and `jae` before loads and stores; a loop indexes with `2 * i + 1`, `len - c`, or a list updated in place through a join.
Evidence: [results](../../bench/perf/heap-parity/README.md), [range pass](../../crates/ms-mir/src/opt/range.rs), [fixture](../../crates/ms-mir/tests/fixtures-opt/list_join_walk.mir).
Verify: `MS_EMIT_OPT=1 ms emit heap.ms` shows `list.get.u`/`list.set.u` in the sift loop; callgrind totals within Rust's.
