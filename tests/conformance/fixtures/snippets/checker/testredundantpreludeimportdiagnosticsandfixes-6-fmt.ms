# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:115 TestRedundantPreludeImportDiagnosticsAndFixes
import (
    range,  # factory
    List  # collection
) from "@std/collections/collections.ms"
