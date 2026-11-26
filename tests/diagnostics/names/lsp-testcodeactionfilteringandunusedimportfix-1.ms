// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:160 TestCodeActionFilteringAndUnusedImportFix
import ListEntry from "@std/collections/collections.ms"

fn answer() Int {
	return 42
}
// expect-error: MS2003 4:8-4:17 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
