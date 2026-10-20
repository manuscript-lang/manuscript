# conform: tags=formatter,lists,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:46 TestRedundantPreludeImportEditorFix
import {
    List, # keep
    ListBuilder,
} from "@std/collections.ms"
fn count() Int: ListBuilder[Int]().freeze().length()+List[Int]().length()
