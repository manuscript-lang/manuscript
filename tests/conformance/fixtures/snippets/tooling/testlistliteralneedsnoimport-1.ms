// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:117 TestListLiteralNeedsNoImport
fn answer() Int {
	items := [1, 2, 3]
	return items.length()
}
// expect-exit: 0
