// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/analysis_test.go:112 TestLocalRenameUsesBindingsAndVersions
fn answer() Int {
	number := 42
	return number
}
// expect-exit: 0
