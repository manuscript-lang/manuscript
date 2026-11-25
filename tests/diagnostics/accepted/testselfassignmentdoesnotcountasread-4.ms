// conform: tags=control-flow,diagnostics,formatter,mutation,tier-core
// conform: phase=check,parse
// conform: origin=pkg/tooling/lint_program_test.go:96 TestSelfAssignmentDoesNotCountAsRead
fn answer() Int {
	var total = 0
	total += 2
	if total > 1 {
		return 1
	}

	return 0
}
// expect-exit: 0
