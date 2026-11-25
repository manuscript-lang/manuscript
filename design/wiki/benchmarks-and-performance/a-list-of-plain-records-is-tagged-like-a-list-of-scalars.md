# A list of plain records is tagged like a list of scalars

Verified (2026-11-25): the PriorityQueue in `graph` swaps 24-byte entries (`HeapEntry{value: Item, order}`) through `list.set.u`, and every swap wrote the list header (pointer, length, capacity) back to the queue record, unchanged, plus a reload of the capacity. LLVM could not drop the stores: a record element was stored without an alias tag, so it might overlap the header, while only elements of scalar lists carried the scalar tag that header memory does not alias. `emit_list.c` `elem_tbaa` now gives the scalar tag to an element that is a record owning nothing (`!mir_needs_drop`): such a record holds no list header, so no differently tagged access can reach its bytes. `graph` 644.3M to 618.5M instructions (-4.0%); the other 22 suite programs changed by less than 0.1%.

A record with a list, string or other owned field keeps no tag: a header-tagged access can lie inside it.

Apply when: a loop over a list of small plain records reloads or stores the list header every iteration.
Evidence: `src/compiler/emit/emit_list.c`, callgrind of `bench/perf/suite/graph` (`sift_down` 237M to about 210M).
Verify: callgrind instruction counts of the suite before and after; `ctest`, `conform`.
