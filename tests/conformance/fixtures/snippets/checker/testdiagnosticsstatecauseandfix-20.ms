// conform: tags=diagnostics,formatter,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:39 TestDiagnosticsStateCauseAndFix
fn f(n Int?) Int {
	return 1 + n
}
// expect-error: MS3001 5:14 operator operands require the same independently known type, found Int + Int?; Int? may be absent; test it first with 'if x != null', or give a default with 'x or default'
