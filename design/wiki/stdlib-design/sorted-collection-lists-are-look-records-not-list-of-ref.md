[Wiki](../index.md) › [Standard-library design](index.md)

# Sorted collection key and value lists are look records, not `List[&T]`

Decision (2026-11-25, #6990): `SortedMap.keys`, `values` and `SortedSet.range`, `values` return `List[SortedItem[T]]`, where `SortedItem` has one `&` field, read as `item.value`. They returned `List[&K]` and copied every element: the checker erases `&` in a type argument, so `out.append(elem)` in a stdlib body lowered to a clone (1000 keys gave 1001 string clones; now 1). Stdlib bodies skip the hidden-copy check, so nothing flagged it, and valgrind and the leak count stay clean because the list owns real copies.

A real `List[&T]` needs a borrowed-element list type in MIR, written types carried to lowering and borrowed variants of `set`, `pop`, `remove` and a consuming `for` ([draft proposal](../../proposals/borrowed-element-lists.md)). Use a look record for a view list until then.

Apply when: adding a stdlib function that returns a list of parts of its receiver.
Evidence: `tests/conformance/fixtures/e2e/stdlib/sorted.ms`, `sorted_map_lists.ms`.
Verify: the counting runtime reports `string_clones=1` for `for k in m.keys()` over a 1000-key `SortedMap[String, Int]`.
