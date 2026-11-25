// conform: tags=alternatives,diagnostics,formatter,match,records,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:62 TestDiagnosticsStateCauseAndFix
enum S {
	A
	B
}

fn f(s S) Int {
	match s {
		A => {
			return 1
		}
		other => {
			return 2
		}
	}
}
// expect-error: MS2001 14:9 'other' is not a case of S; a lone lowercase name binds an Optional's payload, but this is not an Optional; use '_' for a catch-all arm, or one of the cases: A, B
