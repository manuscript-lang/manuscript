// conform: tags=diagnostics
// conform: phase=check
import ListBuilder from "@std/collections/collections.ms"

fn answer() Int {
	unused := 1
	var written = 2
	written = 3
	return 0
	return 1
}
// expect-error: MS2002 3:8-3:19 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
