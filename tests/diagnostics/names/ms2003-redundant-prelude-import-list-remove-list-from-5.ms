// conform: tags=diagnostics
// conform: phase=check
import (
	List,  // keep
	ListBuilder,
) from "@std/collections/collections.ms"

fn count() Int => ListBuilder[Int]().freeze().length() + List[Int]().length()
// expect-error: MS2003 4:5-4:9 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:5-4:10 ""
// expect-error: MS2002 5:5-5:16 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2001 8:19 unknown binding ListBuilder; declare it with 'ListBuilder := ...' before use, define 'fn ListBuilder(...) T { ... }', or import it from a module
