// conform: tags=diagnostics,formatter,match,optional,tier-core
// conform: phase=check,parse
// conform: origin=pkg/checker/hints_test.go:37 TestDiagnosticsStateCauseAndFix
fn f(o Int?) Int {
	match o {
		Some(v) => {
			return v
		}
		None => {
			return 0
		}
	}
}
// expect-error: MS2001 6:9 unknown case Some of Optional; cases: null, some; did you mean 'some'?
// expect-error: MS2001 9:9 unknown case None of Optional; cases: null, some
