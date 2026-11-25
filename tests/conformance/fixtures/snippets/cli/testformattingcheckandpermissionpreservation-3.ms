// conform: tags=control-flow,diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=internal/cli/cli_test.go:187 TestFormattingCheckAndPermissionPreservation
fn value() Int {
	if true { return 3 }
	return 0
}
// expect-exit: 0
