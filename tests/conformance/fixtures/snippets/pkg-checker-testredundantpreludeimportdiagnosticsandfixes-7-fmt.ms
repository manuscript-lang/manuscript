# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/checker/collection_prelude_test.go:116 TestRedundantPreludeImportDiagnosticsAndFixes
import {
    List  # collection
    ,
    range
} from "@std/collections.ms"
