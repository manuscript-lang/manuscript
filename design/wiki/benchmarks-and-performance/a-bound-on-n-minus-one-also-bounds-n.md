[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A bound on `n - 1` also bounds `n`

Verified (2026-11-18, `ms-mir` range analysis): `for x in 1..(n - 1): a.get(y * n + x - 1)` kept every index wrap (`lea`, `test`, `cmov`) and its negative-index branch, because the guard `x < n - 1` narrowed only the SSA value `n - 1`, not `n`, so `y * n` could not be shown non-negative. A comparison now also narrows the operand of a checked add or subtract of a constant (`narrow_back`, three steps deep): the check succeeded, so the arithmetic was exact. A 1000x1000 four-neighbour stencil, 20 sweeps, checked-C comparison: Cranelift 1,949M to 1,412M instructions (C 438M), LLVM 760M to 740M.

Rejected: an unsigned compare before the negative wrap in `expand` (hot path one compare, wrap in a cold block) left Cranelift's count unchanged and made LLVM's `particles` and `stencil` loops 1.5x to 2x slower (the extra join block hid the loop from its vectorizer and address folding). Folding `not (a == b)` into `a != b` in `simplify` saved 1% on a bytecode loop and nothing elsewhere.

Apply when: an index or count comes from `n - c` loop bounds and a bounds or wrap check stays in the machine code.
Evidence: `crates/ms-mir/src/opt/range.rs` (`narrow_back`), test `a_bound_on_n_minus_one_bounds_n`, fixture `fixtures-opt/narrow_through_offset.mir`.
Verify: `list.get.nn` appears for `list.get %l, %p` after `1 <= x < n - 1`, `p = x * n`.
