// conform: tags=diagnostics
// conform: phase=check
import List, ListBuilder from "@std/collections/collections.ms"

fn count() Int => ListBuilder[Int]().freeze().length() + List[Int]().length()
// expect-error: MS2003 3:8-3:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 3:8-3:14 ""
// expect-error: MS2002 3:14-3:25 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2001 5:19 unknown binding ListBuilder; declare it with 'ListBuilder := ...' before use, define 'fn ListBuilder(...) T { ... }', or import it from a module
