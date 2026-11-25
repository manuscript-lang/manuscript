// conform: tags=diagnostics,formatter,lists,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:44 TestRedundantPreludeImportEditorFix
import List from "@std/collections/collections.ms"  // keep

fn count() Int => List[Int]().length()
// expect-error: MS2003 4:8-4:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:1-4:51 ""
