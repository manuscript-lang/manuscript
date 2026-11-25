// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/defaults_test.go:66 TestRenameParameterUsedInDefault
fn combine(first Int = 3, second Int = first) Int {
	return first + second
}
// expect-exit: 0
