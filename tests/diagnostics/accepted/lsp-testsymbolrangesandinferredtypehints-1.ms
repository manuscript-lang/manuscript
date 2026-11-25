// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:145 TestSymbolRangesAndInferredTypeHints
fn answer() Int {
	number := 42
	return number
}

fn later() Int {
	return 2
}
// expect-exit: 0
