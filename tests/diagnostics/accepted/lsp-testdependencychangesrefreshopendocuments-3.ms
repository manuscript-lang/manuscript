// conform: tags=diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/analysis_test.go:101 TestDependencyChangesRefreshOpenDocuments
export fn answer() String {
	return "changed"
}
// expect-exit: 0
