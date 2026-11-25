// conform: tags=diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:95 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int {
	var total = 0
	var other = 0
	other = total + 1
	total += 2
	return other
}
// expect-exit: 0
