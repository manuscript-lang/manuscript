// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/collection_prelude_test.go:111 TestRedundantPreludeImportDiagnosticsAndFixes
import List from "@std/collections/collections.ms"
// expect-error: MS2003 4:8-4:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
