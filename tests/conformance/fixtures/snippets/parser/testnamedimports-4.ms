// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:155 TestNamedImports
import (
	ListEntry,  // first
	MapEntry,
) from "@std/collections/collections.ms"
// expect-error: MS2003 5:5-5:14 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 5:5-5:15 ""
// expect-error: MS2003 6:5-6:13 redundant prelude import MapEntry; remove MapEntry from this import and use its prelude declaration directly
// expect-fix: 5:14-6:14 "  // first\n\t"
