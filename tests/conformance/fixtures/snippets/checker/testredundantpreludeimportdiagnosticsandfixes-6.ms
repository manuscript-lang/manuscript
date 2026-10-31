# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/collection_prelude_test.go:115 TestRedundantPreludeImportDiagnosticsAndFixes
import (
    range,  # factory
    List  # collection
) from "@std/collections.ms"
