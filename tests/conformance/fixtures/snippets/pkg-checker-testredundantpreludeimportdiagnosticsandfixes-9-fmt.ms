# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:118 TestRedundantPreludeImportDiagnosticsAndFixes
from "@std/collections.ms" import (
    range,  # factory
    List
)
