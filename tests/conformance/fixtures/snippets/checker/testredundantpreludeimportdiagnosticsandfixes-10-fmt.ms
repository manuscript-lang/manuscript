# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:119 TestRedundantPreludeImportDiagnosticsAndFixes
import List from "@std/collections.ms"  # keep me
