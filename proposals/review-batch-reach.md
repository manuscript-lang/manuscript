# Batch reach counts for review

## Summary

- Preserve every finding, exact distinct caller count and score.
- Replace repeated reverse traversals for bulk scored changes with SCC condensation and bounded blocks of ancestor bits.
- Keep reverse BFS for at most max(1, ceil(V/64)) scored targets; larger batches first use indexed BFS until measured traversal work exceeds V+E.

## Status

- Implemented 2026-10-28 against `c74ab62f9`; independent skeptical review approved the ancestor-block design and adaptive traversal budget before implementation.
- Implements the requested tooling performance fixes without language or output changes.

## Problem

- Issue #1782 measures 8,000 scored chain nodes at 3,743.76 ms versus 6.99 ms for one changed target.
- Each scored target repeats ordered-set reverse traversal; cycles revisit the entire graph for each query.

## Design

- Return exact zero for targets without incoming edges; choose the traversal strategy from the remaining active targets.
- Classify first and record targets requiring reach; score reach and exported terms afterward, preserving their order.
- If cumulative indexed BFS vertex/edge visits exceed V+E and more than ceil(V/64) queries remain, use shared masks; sparse/disconnected groups stay on cheap BFS.
- For bulk queries, index head entities and condense strongly connected components with iterative Kosaraju traversal.
- Build a caller-component → callee-component DAG; retain topological order.
- For each block of up to 64 original head entities, seed one distinct bit per entity in its SCC.
- Propagate masks forward through the DAG. Each target mask represents exactly the block's distinct original callers, including itself.
- Add `count_ones` of each scored target's mask to its count; subtract exactly one after all blocks. SCC size naturally follows from distinct seeded original vertices.
- Time is O(V+E+ceil(V/64)*(V+E+K)); scratch memory O(V+E+K), independent of transitive closure size.
- Small batches retain the previous lazy BFS; unchanged/body-only entries require no reach work.
- Missing head callee keys cannot participate in a path back into a head target and are omitted from the indexed graph.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `ms-tooling/src/review.rs` | defer reach; private batch helper | reference BFS equality, scores and stable outputs |
| `ms-tooling/src/review/reach.rs` | private indexed SCC and DAG masks | cycles, diamonds, disconnected/self/duplicate edges, generated graphs |

## Alternatives

- Do nothing: preserves measured multi-second bulk latency.
- Indexed BFS only: smallest constant-factor improvement, but still K graph traversals.
- Full ancestor bitsets: similar word operations but O(V²/64) retained memory; rejected for large graphs.
- Direct mask worklist without SCC: fewer lines but repeated edge visits around cycles can erase the word-factor benefit.
- Query-bit propagation and enumerating each set bit: still O(KV) counting; ancestor blocks use popcount instead.

## Staging and verification

- Review this proposal before implementation; compare deterministic graphs to reference BFS and findings.
- Measure chain/ring bulk, one/none changed controls, and source report fixtures with the same local harness before/after.
- Run tooling tests, Rust formatting and focused Clippy. Workspace/native builds are outside the authorized source-only scope.

## Open questions

- None affecting user-visible behavior.
