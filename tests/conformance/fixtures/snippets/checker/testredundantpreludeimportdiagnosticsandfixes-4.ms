// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/checker/collection_prelude_test.go:113 TestRedundantPreludeImportDiagnosticsAndFixes
import List, filled from "@std/collections/collections.ms"
// expect-error: MS2003 4:8-4:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:8-4:14 ""
