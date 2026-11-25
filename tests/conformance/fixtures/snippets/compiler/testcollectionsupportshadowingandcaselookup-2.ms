// conform: tags=diagnostics,lists,modules,stdlib-bytes,stdlib-collections,stdlib-errors,strings,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/collection_prelude_imports_test.go:92 TestCollectionSupportShadowingAndCaseLookup
import (
	Bytes from "@std/bytes.ms",
	ListEntry,
	MapEntry,
	Partition,
	filled,
	map_from_entries from "@std/collections/collections.ms",
	Error, category from "@std/core.ms",
)

fn bytes() Bytes => Bytes([1])

fn build() List[Int] => List[Int]()

fn text_error(message String) Error => Error(message)
// expect-error: MS2003 6:5-6:14 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 6:5-6:15 ""
// expect-error: MS2003 7:5-7:13 redundant prelude import MapEntry; remove MapEntry from this import and use its prelude declaration directly
// expect-fix: 7:5-7:14 ""
// expect-error: MS2003 11:5-11:10 redundant prelude import Error; remove Error from this import and use its prelude declaration directly
// expect-fix: 11:5-11:12 ""
// expect-error: MS2002 11:12-11:20 module does not export category; @std/core.ms exports: Clonable, Closeable, Comparable, Data, Equal, Error, Hashable, Iterator, Optional, Result, Stringable, Writable, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/core.ms"'
