// conform: tags=diagnostics
// conform: phase=check
import MapBuilder from "@std/collections/collections.ms"

type MapBuilder {
	value Int
}
// expect-error: MS2002 3:8-3:18 module does not export MapBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
