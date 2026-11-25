// conform: tags=diagnostics
// conform: phase=check
import (
	Bytes from "@std/bytes.ms",
	ListBuilder,
	MapBuilder,
	SetBuilder,
	filled,
	map_from_entries from "@std/collections/collections.ms",
	ErrorCategory, TextError, category from "@std/errors.ms",
)

fn bytes() Bytes => Bytes([1])

fn build() List[Int] => ListBuilder[Int]().freeze()

fn text_error(message String) TextError => TextError(message)
// expect-error: MS2002 5:5-5:16 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2002 6:5-6:15 module does not export MapBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2002 7:5-7:15 module does not export SetBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2002 10:5-10:18 unknown standard module @std/errors.ms
// expect-error: MS2002 10:20-10:29 unknown standard module @std/errors.ms
// expect-error: MS2002 10:31-10:39 unknown standard module @std/errors.ms
// expect-error: MS2001 17:31 unknown type TextError; declare it with 'type TextError:' / 'enum TextError:' / 'interface TextError:', declare it as a type parameter, or import it
// expect-error: MS2001 15:25 unknown binding ListBuilder; declare it with 'ListBuilder := ...' before use, define 'fn ListBuilder(...) T { ... }', or import it from a module
// expect-error: MS2001 17:44 unknown binding TextError; did you mean 'text_error'?
// expect-fix: 17:44-17:53 "text_error"
