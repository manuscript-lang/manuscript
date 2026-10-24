# conform: tags=diagnostics,lists,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:44 TestRedundantPreludeImportEditorFix
from "@std/collections.ms" import List  # keep

def count() -> Int: List[Int]().length()
