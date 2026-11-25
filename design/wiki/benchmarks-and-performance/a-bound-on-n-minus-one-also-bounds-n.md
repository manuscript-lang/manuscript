[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A bound on `n - 1` also bounds `n`

Verified (2026-11-18, MIR range analysis, `src/compiler/opt/opt_range_refine.c`): `for x in 1..(n - 1) { a.get(y * n + x - 1) }` kept every index wrap (`lea`, `test`, `cmov`) and its negative-index branch, because the guard `x < n - 1` narrowed only the SSA value `n - 1`, not `n`, so `y * n` could not be shown non-negative. A comparison now also narrows the operand of a checked add or subtract of a constant (three steps deep): the check succeeded, so the arithmetic was exact. A 1000x1000 four-neighbour stencil, 20 sweeps, checked-C comparison: LLVM 760M to 740M instructions (C 438M; the Rust Cranelift backend went 1,949M to 1,412M).

Rejected: an unsigned compare before the negative wrap in `expand` (hot path one compare, wrap in a cold block) made LLVM's `particles` and `stencil` loops 1.5x to 2x slower (the extra join block hid the loop from its vectorizer and address folding). Folding `not (a == b)` into `a != b` in `simplify` saved 1% on a bytecode loop and nothing elsewhere.

Apply when: an index or count comes from `n - c` loop bounds and a bounds or wrap check stays in the machine code.
Evidence: `src/compiler/opt/opt_range_refine.c`, `opt_range_prove.c`.
Verify: `list.get.nn` appears for `list.get %l, %p` after `1 <= x < n - 1`, `p = x * n`.
