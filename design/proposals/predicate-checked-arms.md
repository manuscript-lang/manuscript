# Predicate checked arithmetic in if-converted arms

## Summary

- Problem: `dst := if front: b + l else: b + len - 1 - r` stays a data-dependent branch because the arms hold checked arithmetic, which if-conversion refused to speculate; a partition loop then mispredicts about every other element.
- Change: if-conversion hoists arms with checked `+` and `-` on Int: each computes the wrapped result and an overflow flag, and one guard faults when the arm that was taken has its flag set.
- Decision requested: none; the fault, its message and its source position are unchanged.

## Status

Implemented, 2026-11-23.

## Problem

A stable quicksort written in Manuscript (swaps only, ping-pong partition) took about 98 ms for 1M records with 1000 keys, against 60 to 70 ms for the builtin sort. The partition loop sends each element to the front or back of the scratch half; written with wrapping adds, the arms became selects and the sort took 59 to 66 ms. The only difference is the overflow checks: `ifconv` accepted no checked arithmetic ("predicating an overflow check costs about as much as the branch it saves"), true for a predictable branch, false for one that flips on random data.

## Design

`speculatable` accepts `iadd.chk` and `isub.chk` on plain Int operands (sized integers also fault out of range, which a 64-bit flag does not show) with at most two checks per arm. After the arms are hoisted into the head, each check becomes the wrapped op plus a flag: `iadd.overflow` for add, the sign test `((a ^ b) & (a ^ r)) < 0` for sub. A select on the branch condition picks the taken arm's flag and `int_overflow.if` faults on it, with the check's own source location; when the two arms' checks sit at different positions each arm gets its own guard, so the fault names the check that failed. The guard is a rarely taken, predictable branch. A not-taken arm that would overflow no longer faults, because only the taken arm's flag is tested.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_ifconv.c` | predicated checks | `e2e/accept/ifconv-checked-arms` |
| `design/wiki/benchmarks-and-performance` | lesson | none |

## Alternatives

- Do nothing: every data-dependent choice between checked index computations stays a mispredicting branch.
- Wrapping arithmetic in the stdlib sort: fastest (59 to 66 ms) but only for that code; user code with the same shape stays slow.
- Prove the sums cannot overflow: the operands are parameters with no range; the proof would need list-length facts that hold only after the later bounds check.

## Measurement

Predicating every checked arm raised `guard-strcmp` by 12.2% instructions: its `n += 2` sat in a branch around one arm, well predicted, so the flag, select and guard were pure cost. Static cost cannot separate that from the sort partition (both arms compute); what does differ is shape. A branch around one arm usually guards a rare case; a choice between two computed arms is the data-dependent one. Predicated checks therefore apply only when both arms hold instructions; a triangle keeps its branch.

Instruction counts (`tools/perf-counts.ms`, base against this change): `guard-image` +1.2% (inside the 3% bound), every other count within 0.05%, `guard-strcmp` unchanged. Sort partition at 1M records: 98 to about 88 ms.
