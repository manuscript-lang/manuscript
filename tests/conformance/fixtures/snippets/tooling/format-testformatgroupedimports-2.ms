// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/tooling/format/format_test.go:149 TestFormatGroupedImports
import ListEntry, MapEntry from "@std/collections/collections.ms"  // collections
// expect-error: MS2003 4:8-4:17 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:8-4:19 ""
// expect-error: MS2003 4:19-4:27 redundant prelude import MapEntry; remove MapEntry from this import and use its prelude declaration directly
// expect-fix: 4:17-4:27 ""
