# Narrow callback snapshot review

This production slice changes List callback membership capture and three missing
writer detach calls. Production storage remains `[]Value`; the typed representation
is isolated benchmark code. #142 and #87 remain open.

## Correctness boundaries

1. A private, capacity-limited header captures membership. Every prefix writer
   must detach before touching that array. Existing append-only paths can reuse
   capacity beyond captured length. The mutator table covers prepend, replacement,
   removal, splice, fill, both overlap directions/truncation for copy, and reverse.
   Additional cases cover growth then a prefix write, snapshots taken before and
   after detach, and self-splice while a snapshot is live. Native and standalone
   source cases exercise the same edge sequences.
2. The receiver remains the authoritative `*List`. Growth and detach update its
   array field, so aliases and saved methods observe updates. The snapshot header
   stays private to traversal; cloning creates independent outer storage and
   retains nested/recursive/callable references.
3. Snapshot capture sets the non-atomic `shared` flag, just as existing for-loop
   capture does. **Concurrent callback reads without synchronization can race**,
   even if their source bodies only read. The public collection contract already
   requires `Synchronized` for concurrent reads and mutation, with every alias
   using the same lock. The sharing guide now points out this stricter collection
   rule so its generic read-only sentence is not mistaken for an exception.
   No lock-free concurrent collection-read guarantee is added by this change.
4. Raw Go assignments to exported `List.Items` bypass detach. Native adapters
   that mutate a captured list must use the COW-aware runtime operations. This
   requirement already existed for for-loop snapshots and now applies to callback
   snapshots too; a direct external Go write can overwrite captured membership.
   The language/native-operation tests use checked operations, not raw writes.
5. The conservative flag has no release tracking. The first later prefix write
   can copy even after traversal completes. One callback followed by one write
   still pays one membership-array copy, at a different point than eager capture;
   a read-only callback avoids it, and repeated writes reuse detached storage.
6. No mutation order, return identity, stable-sort comparator behavior, equality
   scope, Result/Optional conversion, cancellation or fault site is changed.
   Callback fault/reentry/cancellation and source-frame tests pass. #244's complete
   callback set/output evidence is preserved, and #214's source-call guards remain.

The exact mutation/name wrappers are coordinated with #165: `set`/`remove` must
share the current detached writer implementation, `reverse_in_place` must retain
the detach, and `reversed` must allocate independent outer storage with shallow
element references. Those additive APIs are owned by their separate task.

## Normal-runtime comparison

`normal_pairs.py` compares independent before/after native test binaries built
against the same frozen main. It runs real generated source callbacks, checked
arithmetic, current source-call/record guards and cancellation. Each timed call
gets a fresh shallow clone of one prebuilt 65,536-element list, common to both
variants, so write/reset costs are comparable. The cases are read-only traversal,
one prefix write in the callback, and the first prefix write after it returns.
Checksums and alias updates are checked before timing.

CPU 0, GOMAXPROCS=1, GOGC=100, no GOMEMLIMIT, fixed-seed random within-pair order,
12 pairs at 200ms per case. Compilation and process startup are excluded from
reported `ns/op`. Ratios are geometric means of paired log ratios; intervals
are percentile bootstraps with 10,000 resamples. These describe this host and
workload, and do not guarantee a speedup in every program. Raw trials and binary
hashes are retained beside the results.

Frozen base: `ecba349e`. Go 1.25.1, Linux amd64, Intel Xeon Platinum 8573C.

| Case | after/before time ratio | paired 95% interval | before/after allocated bytes |
| --- | ---: | --- | ---: |
| Read-only callback | 0.927 | 0.879–0.977 | 3,671,326 / 2,622,749 |
| One write inside callback | 1.025 | 0.968–1.092 | 3,672,037 / 3,672,038 |
| First write after callback | 1.041 | 0.965–1.107 | 3,671,791 / 3,671,789 |

The common fresh-input clone adds about 1 MiB to both sides. Read-only traversal
is faster in 9/12 pairs and removes exactly one membership array. The writing
cases have unchanged allocation counts; their timing intervals include equality
and do not exclude modest slowdowns. There is no established writing-path speedup
or claim that delayed copying is free. See `results/narrow-normal-pairs.json`.

```sh
python3 scripts/bench-lists/normal_pairs.py \
  --before /path/to/before.test --after /path/to/after.test \
  --output .artifacts/narrow-pairs --count 12 --cpu 0 --benchtime 200ms
```

Exact-head local/CI/distribution gate results are reported on PR #247. Cancelled
or superseded runs do not count as passes. Broad typed storage and a replacement
for held #238 remain unapproved for production integration.
