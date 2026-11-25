// conform: tags=diagnostics,formatter,strings,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/completion_test.go:141 TestTypedCompletionWhileEditing
fn work() String {
	return "Que|"
}
// expect-exit: 0
