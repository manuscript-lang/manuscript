// conform: tags=diagnostics,records,tier-core
// conform: phase=check
// conform: origin=pkg/checker/hints_test.go:32 TestDiagnosticsStateCauseAndFix
type P {
	x Int
}

fn f(p P) Int {
	return p.y
}
// expect-error: MS2001 9:14 unknown or ambiguous member y on P; available: x
