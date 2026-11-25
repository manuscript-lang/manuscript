// conform: tags=diagnostics
// conform: phase=check
import (
	SetBuilder from "@std/collections/collections.ms",
	CsvOptions from "@std/data/csv.ms",
)

fn example() Void {
	SetBuilder[String]()
	CsvOptions(delimiter: ",", line_ending: "\n")
}
// expect-error: MS2002 4:5-4:15 module does not export SetBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2001 9:5 unknown binding SetBuilder; declare it with 'SetBuilder := ...' before use, define 'fn SetBuilder(...) T { ... }', or import it from a module
