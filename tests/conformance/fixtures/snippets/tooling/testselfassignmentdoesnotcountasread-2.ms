// conform: tags=diagnostics,mutation,tier-core
// conform: phase=check
// conform: origin=pkg/tooling/lint_program_test.go:94 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int {
	var total = 0
	total += 2
	return total
}
// expect-exit: 0
