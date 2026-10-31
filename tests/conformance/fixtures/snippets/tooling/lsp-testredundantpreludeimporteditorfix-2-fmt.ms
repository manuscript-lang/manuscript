# conform: tags=formatter,lists,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:44 TestRedundantPreludeImportEditorFix
import List from "@std/collections.ms"  # keep

fn count() Int: List[Int]().length()
