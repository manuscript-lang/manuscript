// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/checker/collection_prelude_test.go:116 TestRedundantPreludeImportDiagnosticsAndFixes
import (
	List  // collection
	,
	range
) from "@std/collections/collections.ms"
// expect-error: MS2003 5:5-5:9 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 5:5-6:6 "  // collection\n\t"
// expect-error: MS2002 7:5-7:10 module does not export range; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
