// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lsp/features_test.go:57 TestProjectRenameUpdatesImportsLabelsAndAssignments
export fn add(value Int) Int {
	var current = value
	current += 1
	return current
}
// expect-exit: 0
