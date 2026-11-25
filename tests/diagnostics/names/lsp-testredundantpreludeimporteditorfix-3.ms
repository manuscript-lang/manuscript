// conform: tags=diagnostics,formatter,lists,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:45 TestRedundantPreludeImportEditorFix
import List, ListEntry from "@std/collections/collections.ms"

fn count() Int => List[Int]().length() + List[Int]().length()
// expect-error: MS2003 4:8-4:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:8-4:14 ""
// expect-error: MS2003 4:14-4:23 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:12-4:23 ""
