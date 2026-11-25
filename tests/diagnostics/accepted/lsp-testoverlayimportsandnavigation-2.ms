// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/analysis_test.go:21 TestOverlayImportsAndNavigation
export fn answer() Int {
	return 1
}
// expect-exit: 0
