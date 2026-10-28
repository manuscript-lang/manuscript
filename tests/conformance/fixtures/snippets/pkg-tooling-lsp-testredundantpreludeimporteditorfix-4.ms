# conform: tags=diagnostics,lists,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/tooling/lsp/prelude_imports_test.go:46 TestRedundantPreludeImportEditorFix
import {
    List,  # keep
    ListBuilder,
} from "@std/collections.ms"

fn count() Int: ListBuilder[Int]().build().length() + List[Int]().length()
