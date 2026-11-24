# Share shortest effect diagnostic paths

## Summary

- Problem: effect diagnostics repeat graph searches for callers sharing a wide callee.
- Change: compute distances and next edges once per effect requiring diagnostics.
- Decision: share paths only after a bounded amount of ordinary search work.

## Status

Implemented after independent skeptical proposal review, 2026-11-10.
Release measurements repeated on main `ae87acedab5641ffac4179b17e3e0dc442fcca0e`;
repository and exact-head CI gates still determine merge readiness.
Owner direction: “we don’t want to cause regressions or perf slowdowns”.

## Problem

- Measured: release `ms check` for 500/1000/2000 roots sharing a hub with the
  same number of leaves takes median 121/202/524 ms (five trials, one warmup).
- The same 2000-node-width graph with file permission takes 138 ms; roots
  calling the sink directly take 125 ms. Both controls retain the hub/leaves.
- Exact JSON checks establish `2*N+1` effect diagnostics for the denied graph,
  none for the permitted graph, with zero compiler errors.
- Evidence and generator: `bench/perf/effect-reachability/`.
- Verified: `path_to` allocates and searches independently for each violation,
  visiting every hub successor before finding the first leaf's declaring sink.
- N roots therefore repeat at least N² edge inspections, while the graph and
  output path-label counts are O(N). Identifier byte lengths grow logarithmically.
- The existing propagation worklist already addresses the earlier chain problem.

## Design

- Keep graph construction, propagation, permission matching, and effect sets intact.
- Gather violating node indices by effect in the existing node/name order.
- Only effects with violations need a path computation; pure/permitted programs
  must not allocate full distance/next-edge tables.
- For each effect, first use the existing BFS and count inspected nodes/edges.
  Only after cumulative search work exceeds the graph's node-plus-edge count
  build shared tables for remaining requests. Sparse short queries keep their
  existing search cost instead of scanning a large unrelated graph.
- For one effect, seed a reverse breadth-first traversal with its declaring nodes.
- Reuse the existing caller lists and flat node indices; only nodes whose outward
  set contains that effect participate in intermediate paths.
- Distances represent the shortest route to any declaration of that effect.
- Select one next edge per node by shortest distance, then callee label, keeping
  original edge order when labels and distances tie. Ignore direct self edges.
- A node that declares another effect may still need a diagnostic for its body;
  select its first edge from finite-distance outgoing nodes even when its own
  outward set hides this effect.
- Reconstruct each requested path from the preselected edges in output-length time.
- A declaring start can reach itself through a cycle; the current search excludes
  the start as a terminal. If the selected path returns to its start, use the
  original search for that query. Do not treat its own declaration as permission.
- This exceptional cyclic-declaration case retains its existing complexity.
- Process one effect at a time, releasing its distance/next-edge arrays rather
  than retaining a node-by-effect matrix of machine-word indices.
- Retain node indices with emitted violations and stable-sort by node index.
  Within each node, effect-name order remains the original sorted order.
- Keep the first-reference position lookup unchanged.
- No public API, language, diagnostic wording, platform, ownership, or runtime change.

## Components touched

| Component | Change | Test |
| --- | --- | --- |
| `crates/ms-check/src/effect_reach.rs` | Shared shortest paths | Differential graph oracle, cycles, ties, hidden declarations |
| `bench/perf/effect-reachability` | CLI measurements and controls | Exact JSON, native exit/stdout, repeated paired trials |

## Alternatives

- Doing nothing retains the measured 3.8x gap against the permission control.
- Pre-sorting adjacency alone removes repeated sorting but retains N² visits.
- Memoizing complete path vectors across searches stores repeated suffixes and
  needs more complicated context rules for cycles; flat distances/next edges
  avoid that duplication and retain only one effect's working tables.
- Computing paths for every effect regardless of violations adds ordinary-check
  overhead. Build tables only for effects with requested diagnostics.
- Building a full table for one direct violation per effect can introduce quadratic
  work across distinct effects. The graph-sized work budget bounds wasted search;
  qualify sparse-single and many-effect controls alongside the wide-graph win.
- A second-nearest-declaration algorithm could remove the cyclic-start fallback,
  but adds tie and source-exclusion machinery without measured need.

## Stages

- Independently review the algorithm and do-nothing case before implementation;
  then require differential correctness, nonregressing paired controls, repository
  checks and exact-head hosted CI before merging one coherent change.
