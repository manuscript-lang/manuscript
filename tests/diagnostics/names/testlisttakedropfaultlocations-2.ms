// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=tests/e2e/list_take_drop_test.go:18 TestListTakeDropFaultLocations
export fn main() Int {
	copy := [1, 2].METHOD
	part := copy(count: -7)
	return part.length()
}
// expect-error: MS2001 5:20 unknown or ambiguous member METHOD on List[Int]; available: all, any, append, binary_search, chunks, clone, compact, compact_by, concat, contains, copy_within, count, counts, distinct, drop, drop_while, entries, extend, fill, filter, find, find_index, find_last, find_last_index, first, flat_map, fold, fold_right, for_each, get_or, group_by, index_of, insert, is_empty, is_sorted, is_sorted_by, join, keys, last, last_index_of, ...
