# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/collection_prelude_test.go:116 TestRedundantPreludeImportDiagnosticsAndFixes
import (
    List  # collection
    ,
    range
) from "@std/collections.ms"
