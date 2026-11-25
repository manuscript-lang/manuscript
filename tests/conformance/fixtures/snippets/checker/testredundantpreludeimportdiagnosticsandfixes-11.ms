// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/checker/collection_prelude_test.go:120 TestRedundantPreludeImportDiagnosticsAndFixes
import (
	// keep me
	List,
) from "@std/collections/collections.ms"  // tail
// expect-error: MS2003 6:5-6:9 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 4:1-7:41 "\n\t// keep me\n\t"
