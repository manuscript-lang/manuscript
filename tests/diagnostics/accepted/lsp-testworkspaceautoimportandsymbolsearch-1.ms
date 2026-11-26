// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:98 TestWorkspaceAutoImportAndSymbolSearch
export fn multiply(value Int) Int {
	return value
}

fn private() Int {
	return 0
}
// expect-exit: 0
