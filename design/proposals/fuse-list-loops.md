# Fuse a loop that builds a temporary list into the loop that reads it

## Summary

- Problem: `xs.map(f).filter(g).sum()` builds a list per stage and reads each back once.
- Change: a MIR pass runs the reader's body at the builder's push, so the list never exists.
- Decision requested: none. The fault-order change below was approved by Chinmay on 2026-11-23.

## Status

Implemented, 2026-11-23, on top of `4b1e2c3d`. Chinmay chose to let the fault order change when both loops can fault.

## Problem

`closures_20M` runs `xs.map(..).filter(..).sum()` over 1000 elements, 20,000 times. Staged it takes 37 ms; the same loop fused by hand takes 9 ms (same machine, min of 5). The kernel went 46 ms against 34 for checked Rust. LLVM cannot fuse them: the lists are heap blocks behind cleanup registrations.

## Design

After inlining, MIR holds a builder loop (`take S; list.push; put S` into a slot that owns the list) and a reader loop (header `icmp.lt j, list.len L`, reads `list.get L, j`, drops `L`). The pass applies when:

- the elements and the reader's carried values are scalars, and the builder has one push;
- the reader uses the list only by its counter, one drop, one length;
- neither loop calls out, waits, or writes memory other than its own lists and slots;
- the setup between the loops only allocates, registers cleanups or is pure.

It then moves that setup above the builder loop, deletes the list, its slot and cleanup, copies the reader's body to the push (its carried values live in new stack slots the backend promotes to registers), and sends its back edges to the rest of the builder body. One fusion per call; the pipeline simplifies and calls again, so chains fuse stage by stage.

Fault order: if both loops can fault, the fault reported first may come from the reader. The program faults either way. The Rust lowering fuse had the same rule.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `src/compiler/opt/opt_fuse.c`, `opt_pipeline.c` | the pass, first late step | `e2e/accept/list-chain-fusion` |
| `design/wiki/benchmarks-and-performance` | lesson | none |

## Alternatives

- Do nothing: 2x on `closures_20M`; every list pipeline pays an allocation per stage.
- Fuse in lowering, as the Rust code did: matches only lambda literals with no calls, and `closures_20M` did not fuse in the C port. The MIR form needs no source pattern.
- Keep the fault order exactly: needs a replay path, which is much more work. Rejected by Chinmay.
- Owned elements (strings, records): need ownership moved through the push. Left for a later change.
