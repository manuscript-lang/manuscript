# conform: tags=diagnostics,lists,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:45 TestRedundantPreludeImportEditorFix
from "@std/collections.ms" import ListBuilder, List

def count() -> Int: ListBuilder[Int]().freeze().length() + List[Int]().length()
