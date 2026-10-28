# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/collection_prelude_test.go:118 TestRedundantPreludeImportDiagnosticsAndFixes
import {
    range,  # factory
    List
} from "@std/collections.ms"
