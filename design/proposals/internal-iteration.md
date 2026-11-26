# Internal iteration for lazy chains: a `for_each` hook so `filter` is an `if`, not an inner loop

* Status: **Proposed** (2026-11-26), for the owner's decision
* Authors: [Claude](https://claude.ai/code)
* Needed by: [lazy-iterator-chains](lazy-iterator-chains.md) stage 4 (lazy `List.map`/`List.filter` and removing the scalar fusion lowering)
* Direction: Chinmay, 2026-11-25: lazy chains in Manuscript, no wall-time loss beyond noise

## Summary

- Problem: a lazy `filter` written as `next()` (loop until an item passes) becomes an inner loop inside the consumer's loop, which LLVM neither unrolls nor vectorizes. `map` then `filter` then `fold` over 20M ints, five rounds: lazy 0.37 to 0.39 s, the fused loop 0.23 s.
- Change: adapters and consumers walk by passing the loop body in (`for_each(visit fn(T) Bool) Bool`), so `filter` is `if keep(x) { return visit(x) }` inside the source's single loop. `Iterator[T]` itself does not change.
- Decision requested: add the `Folding[T]` interface below, and accept the optimizer work in "What it needs".

## Motivation (measured 2026-11-26, x86-64, `ms` release)

| Program (20M ints x 5) | CPU s |
| --- | --- |
| `for x in xs { y := x*3+r; if y%2==0 { acc += y } }` and the eager fused `map.filter.fold` | 0.23 |
| `xs.iter().seq().map(..).fold(..)` (no filter) against `xs.map(..).fold(..)` | 0.23 against 0.20 |
| `xs.iter().seq().map(..).filter(..).fold(..)` | 0.37 to 0.39 |
| the same loop hand-written as `while` with a skip branch | 0.33 |
| one `each(visit)` call with a closure body | 0.225 |
| two nested `each` adapters (`Mapped.each` wraps `visit`) | 0.61 |

Post-LLVM IR shows the cause: the skip edge makes an inner loop (`b7.outer`/`b7`) nested in the per-kept-item loop, so the 4x unroll the fused loop gets does not happen. Removing the sign test, making the add no-wrap (`MirFunc.exact` is already computed, emitting `nsw` changed nothing) and merging back edges (a prototype pass: the `while` loop dropped 0.33 to 0.21, instructions +1 to 2% on dedupe, grep, report, so dropped) do not change the filter chain: the nesting is real in the program.

## Proposed solution

```manuscript
// A refinement of Iterator for sources that can walk themselves.
export interface Folding[T] {
	var fn next() T?
	// Calls `visit` on each item in order; stops and answers false when `visit` does.
	var fn for_each(visit fn(T) Bool) Bool
}

fn var Filtered[I Folding[&T], T].for_each(visit fn(&T) Bool) Bool {
	return self.source.for_each(item => not self.keep(item) or visit(item))
}
```

`Seq[I Folding[T], T]` consumers (`fold`, `count`, `collect`, `for`) call `for_each`; `map` and `filter` build adapters that forward it. A user iterator that only has `next` joins with `Walk(it)`, a one-line adapter whose `for_each` is the loop over `next`. `Iterator[T]` and `for x in it` are untouched, so no existing program changes.

## What it needs

- The optimizer must inline a callback that closes over another callback. Today a single `each(visit)` with a closure literal inlines (0.225 s) but `Mapped.each(x => visit(self.transform(x)))` does not (0.61 s): `opt_inline_closure.c` knows module-wide capture-free closures and closures stored in records, not a capture that is itself a known closure. Without this the design is slower than today's.
- `Folding` as a refinement needs interface extension; if it does not exist, the interface repeats `next`.

## Alternatives considered

- Keep external iteration and accept 1.6x on filter chains: breaks the no-wall-loss bar, so the scalar fusion lowering stays and lazy `List.map`/`filter` cannot replace it.
- Add `for_each` to `Iterator` itself: every iterator must implement it, and `for` over a record with `next` only (all of today's) breaks; rejected.
- Flatten in the compiler (single back edge, no-wrap flags, unswitching the skip loop): measured above, no effect on the chain.
- Keep fusion for scalar chains and use lazy chains only elsewhere: leaves two paths and the name-keyed lowering the owner rejected.

## Testing and expected result

Prototype first, behind a test: nested `for_each` adapters over a list reach 0.23 s (the fused loop) only if the closure-through-capture inlining lands; target is within 3% of `bench/perf` fused times on dedupe-style chains, instruction counts by callgrind. A result above 0.25 s keeps the idea unmerged.
