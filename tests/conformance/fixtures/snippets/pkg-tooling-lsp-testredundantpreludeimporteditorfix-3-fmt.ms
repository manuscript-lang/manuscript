# conform: tags=formatter,lists,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:45 TestRedundantPreludeImportEditorFix
from "@std/collections.ms" import ListBuilder, List

def count() -> Int: ListBuilder[Int]().build().length() + List[Int]().length()
