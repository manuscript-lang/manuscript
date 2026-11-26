// conform: tags=diagnostics,formatter,modules,records,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/build/compiler_test.go:592 TestGroupedImportResolutionErrors
import MapEntry from "@std/collections/collections.ms"

type MapEntry {
	value Int
}
// expect-error: MS2003 4:8-4:16 redundant prelude import MapEntry; remove MapEntry from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
// expect-error: MS2001 6:1 declaration MapEntry reuses a prelude name; rename it, because MapEntry always refers to the standard declaration
