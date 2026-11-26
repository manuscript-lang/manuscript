[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A bounds check that stays in a heap loop is a lost range fact

Verified (2026-11-12): a hole-based binary heap in Manuscript executed 56.0M instructions against Rust's `BinaryHeap` at 47.1M for 100k enqueues and dequeues; the gap was four bounds checks per sift level, not code quality. The range pass (`src/compiler/opt/opt_range*.c`) lost the facts for four reasons: a block parameter joining lists of different origins made every derived list `Mixed`; `shl` was not modeled (`2 * at + 1` became top); widening went straight to the maximum `Int`, where that step wraps and drops the other bound in a cycle narrowing cannot fix; and a relation to `len - 2` was pruned because nothing reads `len - 2` later. After the fix the heap is 46.0M, under Rust.

Apply when: an equivalent program emits more instructions than Rust and the extra ones are compares and `jae` before loads and stores; a loop indexes with `2 * i + 1`, `len - c`, or a list updated in place through a join.
Evidence: [results](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/heap-parity/README.md), range pass, fixture.
Verify: `MS_EMIT_OPT=1 ms build --emit mir heap.ms` shows `list.get.u`/`list.set.u` in the sift loop; callgrind totals within Rust's.

Verified (2026-11-12, merge sort kernel, 89.0M to 67.1M, Rust 65.2M): two more ways the range pass loses a fact. An `iadd.chk`/`imul.chk` it converts to the unchecked op was then evaluated as wrapping (top when the bound is wide), so a doubling or counting loop variable lost its lower bound on the next round: converted results keep the checked interval. And the refine step ignored a refinement that was disjoint from an early interval, leaving a stale interval below zero that a loop parameter kept forever: it now takes the refinement. Lists in `var` swaps are `opt<list>`; length origins flow through `opt.some`/`opt.get`/`opt.unbox`.
Evidence: [kernel results](https://github.com/manuscript-lang/manuscript/blob/48b25d38/bench/perf/kernel-parity/README.md), fixture (`expect-opt-mir-absent`).

Verified (2026-11-12, matmul kernel, 155.0M to 130.9M, Rust 122.6M): `i * n + j` with `i, j < n` paid an overflow `jo` per index. A dominating checked `n * n` proves `x * n` and `x * n + j` stay below it, so the range prover (`src/compiler/opt/opt_range_prove.c`) converts them to the unchecked ops without symbolic intervals. Dropping the redundant bounds check after a `get` of the same index changed nothing, because LLVM already merged it.
Evidence: fixture.
