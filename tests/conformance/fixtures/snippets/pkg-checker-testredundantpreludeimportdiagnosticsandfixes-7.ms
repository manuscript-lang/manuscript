# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/checker/collection_prelude_test.go:116 TestRedundantPreludeImportDiagnosticsAndFixes
from "@std/collections.ms" import (
    List  # collection
    ,
    range
)
