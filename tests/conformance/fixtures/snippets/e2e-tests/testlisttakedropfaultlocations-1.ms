// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=tests/e2e/list_take_drop_test.go:13 TestListTakeDropFaultLocations
export fn main() Int {
	values := [1, 2]
	part := values.METHOD(-7)
	return part.length()
}
// expect-error: MS2001 6:20 unknown or ambiguous member METHOD on List[Int]; available: all, any, append, binary_search, chunks, clone, compact, compact_by, concat, contains, copy_within, count, counts, distinct, drop, drop_while, entries, extend, fill, filter, find, find_index, find_last, find_last_index, first, flat_map, fold, fold_right, for_each, get_or, group_by, index_of, insert, is_empty, is_sorted, is_sorted_by, iter, join, keys, last, ...
