// conform: tags=diagnostics,optional,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:30 TestDiagnosticsStateCauseAndFix
type Optional {
	x Int
}

fn f(o Int?) Int {
	return 0
}
// expect-error: MS2001 4:1 declaration Optional reuses a prelude name; rename it, because Optional always refers to the standard declaration
