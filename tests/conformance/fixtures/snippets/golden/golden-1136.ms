// conform: tags=diagnostics
// conform: phase=check
import ListBuilder from "@std/collections/collections.ms"

A := 1
B := 2

fn f() Int {
	return A + B
}
// expect-error: MS2002 3:8-3:19 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
