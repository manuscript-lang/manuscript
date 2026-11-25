// conform: tags=diagnostics
// conform: phase=check
fn bad() Void {
	void
}

import List, ListBuilder from "@std/collections/collections.ms"
// expect-error: MS2003 7:8-7:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 7:8-7:14 ""
// expect-error: MS2002 7:14-7:25 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
