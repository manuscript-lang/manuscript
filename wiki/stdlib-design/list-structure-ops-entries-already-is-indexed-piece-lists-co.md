[Wiki](../index.md) › [Standard-library design](index.md)

# List structure ops: `entries()` already is `indexed`; piece lists come from one runtime call

Decision: `List.entries()` (`ListEntry` with `index`, `value`) covers the "walk with an index" need, so no `indexed()` alias was added. `zip` returns `Pair[T, U]` and `partition` returns `Partition[T]`, both exported from `@std/collections/collections.ms` but not prelude names, so user types called `Pair` keep working. `chunks`/`windows` share `msrt_list_pieces`; `zip` and `partition` lower to loops with no closure for `zip`. A non-positive size faults.


Apply when: adding List methods that return records or nested lists.
Evidence: `tests/e2e/testdata/stdlib/list-structural-ops.ms`, `snippets/list-{chunks,windows}-zero-fault`.
Verify: `ms test tests/e2e/testdata/stdlib/list-structural-ops.ms`; `make stdlib-bench BENCHFILTER=list.` shows zip 2, chunks 7, windows 70, partition 9 ns per element.
