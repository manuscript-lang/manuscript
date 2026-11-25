// conform: tags=alternatives,diagnostics,formatter,match,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:35 TestDiagnosticsStateCauseAndFix
enum S {
	A
	B
	C
}

fn f(s S) Int {
	match s {
		A => {
			return 1
		}
	}

	return 0
}
// expect-error: MS3050 11:5 non-exhaustive match; missing cases: B, C, or add a final '_ => ...' arm; add the arms 'B => ...', 'C => ...'
