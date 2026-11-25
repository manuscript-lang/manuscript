// conform: tags=diagnostics,formatter,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:36 TestDiagnosticsStateCauseAndFix
fn f() Int {
	return "a" + 1
}
// expect-error: MS3001 5:16 operator operands require the same independently known type, found String + Int; convert one side so both have one type (e.g. interpolate into text with f"{value}", or convert between Int and Float)
