// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/collection_prelude_test.go:118 TestRedundantPreludeImportDiagnosticsAndFixes
import (
	range,  // factory
	List
) from "@std/collections/collections.ms"
// expect-error: MS2002 5:5-5:10 module does not export range; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2003 6:5-6:9 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 5:10-6:9 "  // factory\n\t"
