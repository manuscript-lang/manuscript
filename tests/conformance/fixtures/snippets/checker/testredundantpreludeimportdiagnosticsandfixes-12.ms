// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/checker/collection_prelude_test.go:129 TestRedundantPreludeImportDiagnosticsAndFixes
import List, Map, Set from "@std/collections/collections.ms"
// expect-error: MS2003 4:8-4:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:8-4:14 ""
// expect-error: MS2003 4:14-4:17 redundant prelude import Map; remove Map from this import and use its prelude declaration directly
// expect-fix: 4:14-4:19 ""
// expect-error: MS2003 4:19-4:22 redundant prelude import Set; remove Set from this import and use its prelude declaration directly
// expect-fix: 4:17-4:22 ""
