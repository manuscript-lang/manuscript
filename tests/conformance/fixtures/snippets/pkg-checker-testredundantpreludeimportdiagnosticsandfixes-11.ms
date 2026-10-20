# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/collection_prelude_test.go:120 TestRedundantPreludeImportDiagnosticsAndFixes
import {
    # keep me
    List,
} from "@std/collections.ms" # tail
