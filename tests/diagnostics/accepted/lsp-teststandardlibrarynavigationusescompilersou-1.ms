// conform: tags=diagnostics,formatter,lists,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:203 TestStandardLibraryNavigationUsesCompilerSources
fn count(values List[String]) Int {
	return values.length()
}
// expect-exit: 0
