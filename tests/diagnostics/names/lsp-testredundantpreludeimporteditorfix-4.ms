// conform: tags=diagnostics,formatter,lists,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/prelude_imports_test.go:46 TestRedundantPreludeImportEditorFix
import (
	List,  // keep
	ListEntry,
) from "@std/collections/collections.ms"

fn count() Int => List[Int]().length() + List[Int]().length()
// expect-error: MS2003 5:5-5:9 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 5:5-5:10 ""
// expect-error: MS2003 6:5-6:14 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 5:9-6:15 "  // keep\n\t"
