# Two arms that run the same operations are one block with selects

`if b < a { dst[k] = b; j += 1 } else { dst[k] = a; i += 1 }` stayed two branches because each arm holds a checked store, so `ifconv` (pure arms only) left it. The branch mispredicts on random data. A bottom-up merge sort over `List[Int]` ran 93 ms against 68 ms for the same loop in C with bounds checks, at the same instruction count; the same code written with `v = if ..` selects ran 61 ms.

The `twins` pass (`src/compiler/opt/opt_twins.c`, after `ifconv` in the function rounds) merges the two arms of a branch when they run the same operations: same operations, parameters, terminator kind and shared successors, with operands the same value, the same position in each arm, or a scalar that differs. Differing external scalars become block parameters; a scalar from one arm mixed with another is chosen by a side flag. Single-predecessor successors merge recursively (the bounds-check fault blocks), then a branch whose two edges reach one block becomes `select`s.

- Measured (2026-11-23): merge sort over 1M Ints 93 to 66 ms, C with checks 68 ms.
- Sound only for arms whose entry owned-value sets agree, so it starts at one branch whose arms each have that branch as their only predecessor and takes scalar parameters only. The verifier rejects any merge that breaks that; merging two fault blocks reached from different places did, which is why the merge works on the whole arm tree from the branch.
- A differing constant is not merged as an instruction operand: selecting between `1` and `2` hides the constant from range analysis and the `exact` bits. Differing results must have equal `exact` bits.
- Evidence: fixture `e2e/accept/twin-arms`.
