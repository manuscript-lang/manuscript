# conform: tags=diagnostics,lists,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:45 TestRedundantPreludeImportEditorFix
import ListEntry, List from "@std/collections.ms"

fn count() Int: List[Int]().length() + List[Int]().length()
