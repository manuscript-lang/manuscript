// conform: tags=diagnostics,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lsp/features_test.go:99 TestWorkspaceAutoImportAndSymbolSearch
fn answer() Int {
	return mul
}
// expect-error: MS2001 5:12 unknown binding mul; declare it with 'mul := ...' before use, define 'fn mul(...) T { ... }', or import it from a module
