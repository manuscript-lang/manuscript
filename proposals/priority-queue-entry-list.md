# PriorityQueue as one list of entries

## Summary

- Problem: `PriorityQueue` runs 1.1 to 1.25x Rust's `BinaryHeap` (#1679). A third of the remaining instructions are the second `orders` list (swaps and bounds checks).
- Change considered: one `List[Entry[T]]` of `{value, order}`, with `List.swap` inline for record elements without drop glue (`mutate_any` in `crates/ms-lower/src/native.rs`: a `needs_drop` test plus multi-word loads and stores; the prototype changed one condition and reused the scalar path), and a way to move a field out of a bound variable (`ownership/walk.rs` has a `lend` path for fields that may already cover part of this; not investigated).
- Result of the prototype (`Int` keys only): 81.5M to 72.4M instructions (-11%); wall time within noise at 100k and 1M keys, so the gain is unmeasured, not shown absent.
- Cost: a compiler change and possibly a language rule (field moves out of a variable), for no measured time win.
- Decision requested: do not build it; keep the two-list heap; leave #1679 open as a documented 1.1 to 1.25x.

## Status

Proposal, 2026-10-27, checked against `b2a6f03f` on `main`. Not pursued after the prototype and a skeptical review, which agreed with not building but asked that the evidence be stated as unmeasured rather than absent (applied). Direction from the project thread: close the remaining Rust gaps in #1679; write this proposal and have it reviewed before implementing.

## Problem

- Measured, `bench/perf/datastructures/run.sh 7`: 90 to 96 ns per op against Rust 77 to 79 (shared host, noisy).
- Measured, callgrind, 100k enqueue and dequeue: 81.5M instructions (Rust 44.9M). Dropping the `orders` swaps gives 71.6M; that variant breaks FIFO ties, so the 10M to 16M cost of the second list is indicative only.
- Hypothesis (not proven for this case): the range analysis cannot tie `orders.length()` to `heap.length()`. Both are fields loaded from the queue record, so their equal length is an invariant the SSA values do not show (`crates/ms-mir/src/opt/range.rs` module doc: "fresh memory reads start new origins"; its `first_field_read` handling was not checked for two fields of one record).
- Non-goals: changing `peek` (an owned `Optional[T]` return, an API change); the user comparator's own checked subtraction.

## Design

- Replace `heap: List[T]` and `orders: List[Int]` with `heap: List[Entry[T]]`, where `Entry[T]` has `value: T` and `order: Int`.
- Extend the inline scalar swap in `mutate_any` to records without drop glue (`Module::needs_drop(ty)` is false). Elements with drop glue keep the runtime swap.
- `dequeue` needs `value` out of the popped entry. Today this fails: `cannot move 'entry.value' out of 'entry': only a whole variable can move` (`crates/ms-check/src/ownership/walk.rs:2080`). The prototype used `entry.value.clone()`, which costs a clone per dequeue for non-scalar `T`; avoiding it needs a new rule that a field moves out of a variable that is not used again. That is a language change.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-lower/src/native.rs` | inline swap for plain records | MIR expectation test in `crates/ms-build/tests/lower` |
| `crates/ms-check/src/ownership/walk.rs` | field move out of a dead variable | conformance accept and reject cases |
| `stdlib/queue.ms` | one entry list | `tests/e2e/testdata/stdlib/queues.ms` |
| docs, formatter, LSP | unchanged unless the move rule lands | none |

## Alternatives

- Do nothing (chosen): two lists, 81.5M instructions, 90 to 96 ns per op.
- One list with swap through the runtime (measured): 190M instructions, worse.
- Clamp the loop to the shorter of the two lists (measured): 86.4M against 87.8M, no real change.
- Entry list with the inline record swap and a clone in `dequeue` (the prototype): 72.4M instructions. process best of 15 at 100k keys was 17.07 ms against 16.77 ms for two lists; at 1M keys (best of 9, two rounds) 270 to 325 ms against 280 to 300 ms. Shared host, no cache or branch counters, no record or string keys: inside the noise, not a measured zero.

## Staging and verification

- Not staged. Gate for reopening: a wall-time win of at least 10% over three `run.sh 7` rounds on a quiet host, from a prototype that also avoids the clone.

## Open questions

- Does the owner want field moves out of dead variables for other reasons? If so this proposal's cost drops and it is worth re-measuring on a quiet host. Recommendation: no, until a measured win exists.
