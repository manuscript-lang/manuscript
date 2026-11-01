# conform: tags=formatter,lists,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:46 TestRedundantPreludeImportEditorFix
import (
    List,  # keep
    ListEntry,
) from "@std/collections/collections.ms"

fn count() Int: List[Int]().length() + List[Int]().length()
