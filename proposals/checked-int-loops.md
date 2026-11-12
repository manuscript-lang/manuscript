# Vectorizing checked `Int` loops

## Summary

- Problem: loops that add, multiply or accumulate `Int` stay scalar because each checked operation exits to a fault; wrapping C vectorizes the same loop.
- Change: prove more accumulations cannot overflow (range pass), not speculate or replay. A sum of values that are small by type or range is a bounded counter.
- Decision requested: none; the rule extends the existing bounded-counter assumption.

## Status

Implemented 2026-11-12 on `claude/project-thread-yxfpqx-narrow-sums`. The "do nothing" and "replay" alternatives were measured first.

## Problem

`y[i] = y[i] + x[i] * 3` over 4000 `Int`, 50,000 passes (Release LLVM, 4 vCPU VM): 0.15 s in Manuscript, 0.06 s for the same loop with wrapping C. `s += list.get(i)`: 0.12 s against C's checked scalar 0.07 s.

LLVM cannot vectorize these loops: `sadd.with.overflow` reductions are not recognized (`loop not vectorized: value that could not be identified as reduction is used outside the loop`), and an uncountable early exit with stores is not supported even with `-enable-early-exit-vectorization(-with-side-effects)` (LLVM 23.1.1).

## Design

Rejected measurement first (clang -O3 -mavx2, same machine, 200M elements):

| shape | seconds |
| --- | ---: |
| checked scalar `y[i] += x[i]*3` | 0.134 |
| chunked: vector flag-OR pass per 256 elements, then wrapping pass, scalar replay on overflow | 0.205 |
| wrapping | 0.060 |
| checked scalar sum | 0.072 |
| chunked sum with an `__int128` chunk total | 0.086 |

- The ceiling of any checked-to-wrapping rewrite is about 2x for add and multiply loops, and a 64-bit multiply overflow test has no AVX2 form, so the extra pass loses. The structural thread measured the same for a per-pass flag.
- A chunk total in range does not prove every prefix is in range, so the replay design also needs a prefix argument. Not built.
- What does pay: removing the check. The range pass (`crates/ms-mir/src/opt/range.rs`) already assumes a loop-carried `Int` that starts below `2^40` and steps by a constant of at most `2^16` stays below `i64::MAX/2` (reaching it takes more than `2^46` iterations).
- Extension: the step may be any value whose interval lies in `[-2^16, 2^16]` (`step_range`), and a widened narrow integer (`conv` from `UInt8`, `Int8`, `Int16`, `UInt16`, `Int32` that fits) has the interval of its type. Steps of both signs bound the counter to `[i64::MIN/2, i64::MAX/2]`.
- Result: `s += bytes.get(i).to_int()` loses its check and LLVM vectorizes it.

```
fn sum(x: Bytes) Int:
	var s = 0
	var i = 0
	while i < x.length():
		s += x.get(i).to_int()
		i += 1
	return s
```

- Unchanged faults: `s += s` and an `Int` addend of unknown range keep `iadd.chk` (`numeric-faults`, `counter-steps-keep-overflow-faults`, and a run of `s += s` that still faults).
- `UInt32` addends exceed the step limit and keep the check: `2^32` over `2^46` passes would pass `2^62` only on a run that cannot finish.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-mir` range pass | `step_range`, `Conv` interval, mixed-sign bound | `opt_range::a_sum_of_narrow_values_is_unchecked`, `induction_variable_is_unchecked` |
| conformance | exact byte and `Int8` sums | `e2e/accept/narrow-sums-keep-values` |

## Alternatives

- Chunk, flag, replay: measured above, slower than the scalar loop on multiply, equal on add.
- Wrapping arithmetic with a sticky flag tested at loop exit: changes which statement faults and what survives a fault; the structural thread measured no gain.
- Do nothing: leaves byte checksums and histograms 5x behind C.
- `UInt32` and `Int` addends of unknown range: need a real proof (loop trip count times value bound), out of scope.

## Open questions

- Loops that sum `Int` values with a known bound below `2^16` computed in the program (for example `x % 100`) already qualify; whether to raise `COUNTER_STEP_MAX` to `2^24` is left to a separate change.
