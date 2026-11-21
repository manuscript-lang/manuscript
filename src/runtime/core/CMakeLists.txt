add_library(ms_core STATIC alloc.c context.c stack.c timers.c queue.c frames.c record.c isolate.c watch.c unwind.c fault.c sched.c segment.c park.c token.c task.c eq.c fault_kept.c fault_abi.c task_abi.c obj.c promise.c promise_end.c promise_wait.c promise_abi.c promise_remote.c group.c pipe.c cancel.c worker.c)
ms_target_defaults(ms_core)
target_link_libraries(ms_core PUBLIC ms_sys ms_base mimalloc)

add_executable(core_alloc_unit alloc_unit.c)
ms_target_defaults(core_alloc_unit)
target_link_libraries(core_alloc_unit PRIVATE ms_core)
add_test(NAME core_alloc COMMAND core_alloc_unit)

# Unit test of pure data structures only; the corpus is the gate (plan rule 2).
add_executable(core_unit core_unit.c)
ms_target_defaults(core_unit)
target_link_libraries(core_unit PRIVATE ms_core)
add_test(NAME core_unit COMMAND core_unit)

# Value natives of the runtime core: strings, bytes, lists, maps, numbers and text formatting.
add_library(ms_values STATIC
  ascii_chars.c
  bits.c
  bytes.c
  bytes_text.c
  index_fault.c
  list.c
  list_derive.c
  list_edit.c
  list_fault.c
  list_range.c
  map.c
  map_build.c
  num.c
  num_text.c
  set.c
  slot.c
  sort.c
  sort_ints.c
  string_case.c
  string_cut.c
  string_lists.c
  string_join.c
  string_make.c
  string_normalize.c
  string_quote.c
  string_query.c
  string_split.c
  unicode_case_tables.c
  unicode_norm_index.c
  unicode_norm_leaf.c
  unicode_norm_pool.c
  unicode_norm_records.c)
ms_target_defaults(ms_values)
target_link_libraries(ms_values PUBLIC ms_base)
